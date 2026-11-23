# frozen_string_literal: true

require "tsort"

module FlowchartRuntime
  class FormulaError < StandardError; end

  # FlowchartRuntime::FormulaCompiler
  #
  # NOTE on the hand-rolled tokenizer/parser below (unlike its sibling
  # ExpressionEvaluator, which delegates to the dentaku gem): this is a
  # formula-to-SQL *transpiler*, not an evaluator. It emits SQL fragments
  # (json_extract(entity_entries.data, '$.field'), CAST(... AS NUMERIC),
  # ROUND/COALESCE/... SQL functions) that run inside generated column
  # expressions — dentaku evaluates a formula to a Ruby value and has no
  # SQL-emission surface, so no established gem covers this need.
  #
  # Re-evaluated 2026-07-15: reusing dentaku 3.5.7 purely as the parser front-end
  # (Calculator#ast → SQL visitor) was prototyped and REJECTED on evidence — its
  # parser type-checks arithmetic at parse time and raises Dentaku::ParseError on
  # string-literal concatenation (`name + "x"`, `"a" + "b"`), which this grammar
  # validly compiles to SQL today. Swapping would break existing user formulas.
  # Only the dependency ordering (stdlib TSort) that a library *does* cover is
  # delegated; the recursive-descent parser stays hand-rolled by necessity and
  # is golden-tested in the compiler spec.
  module FormulaCompiler
    class Error < FormulaError; end

    MAX_LENGTH = 1000
    NUMERIC_HTML_TYPES = %w[number range currency].freeze
    SUPPORTED_FUNCTIONS = %w[ROUND ABS COALESCE UPPER LOWER LENGTH].freeze

    TOKEN_SPEC = [
      [:NUMBER,  /\A\d+(\.\d+)?/],
      [:STRING,  /\A"([^"\\]*)"/],
      [:IDENT,   /\A[A-Za-z_][A-Za-z0-9_]*/],
      [:LPAREN,  /\A\(/],
      [:RPAREN,  /\A\)/],
      [:COMMA,   /\A,/],
      [:PLUS,    /\A\+/],
      [:MINUS,   /\A-/],
      [:STAR,    /\A\*/],
      [:SLASH,   /\A\//]
    ].freeze

    module_function

    def compile(formula, schema_fields, resolved_calculated = {})
      return nil if formula.nil? || formula.to_s.strip.empty?
      formula = formula.to_s.strip
      raise Error, "Formula too long (max #{MAX_LENGTH})" if formula.length > MAX_LENGTH

      field_map = build_field_map(schema_fields)
      tokens = tokenize(formula)
      parser = Parser.new(tokens, field_map, resolved_calculated)
      parser.parse
    end

    def compile_all(schema_fields, resolved: {})
      calculated = schema_fields.select { |f| f["type"] == "Calculated" }
      return [] if calculated.empty?

      seeded = (resolved || {}).to_h.transform_keys(&:to_s)
      data_slugs = schema_fields.reject { |f| f["type"] == "Calculated" }.map { |f| f["name_slug"] }.to_set
      calc_slugs = calculated.map { |f| f["name_slug"] }.to_set
      all_slugs = data_slugs | calc_slugs | seeded.keys.to_set

      deps = {}
      calculated.each do |field|
        next if seeded.key?(field["name_slug"])

        formula = field["formula"].to_s
        refs = formula.scan(/\b([A-Za-z_][A-Za-z0-9_]*)\b/).flatten
        refs = refs.select { |r| all_slugs.include?(r) }
        calc_deps = refs.select { |r| calc_slugs.include?(r) && !seeded.key?(r) }
        if calc_deps.include?(field["name_slug"])
          raise Error, "Circular dependency detected: #{field['name_slug']} references itself"
        end
        deps[field["name_slug"]] = calc_deps
      end

      sorted = topological_sort(deps)

      resolved_acc = seeded.dup
      sorted.filter_map do |slug|
        next if seeded.key?(slug)

        field = calculated.find { |f| f["name_slug"] == slug }
        sql = compile(field["formula"], schema_fields, resolved_acc)
        resolved_acc[slug] = sql
        { name: slug, sql: sql }
      end
    end

    def build_field_map(schema_fields)
      map = {}
      (schema_fields.is_a?(Array) ? schema_fields : []).each do |f|
        next unless f.is_a?(Hash) && f["name_slug"]
        map[f["name_slug"]] = {
          slug: f["name_slug"],
          html_type: f["html_type"] || "text",
          type: f["type"] || "String",
          calculated: f["type"] == "Calculated",
          formula: f["formula"]
        }
      end
      map
    end

    def tokenize(source)
      tokens = []
      pos = 0
      while pos < source.length
        if source[pos] =~ /\s/
          pos += 1
          next
        end
        matched = false
        TOKEN_SPEC.each do |type, pattern|
          match = source[pos..].match(pattern)
          next unless match
          tokens << [type, match[0]]
          pos += match[0].length
          matched = true
          break
        end
        raise Error, "Unexpected character '#{source[pos]}' at position #{pos}" unless matched
      end
      tokens << [:EOF, nil]
      tokens
    end

    # Dependency ordering via Ruby's stdlib TSort (dependencies first),
    # with cycle detection mapped onto FormulaError.
    def topological_sort(deps)
      DependencyGraph.new(deps).tsort
    rescue TSort::Cyclic => e
      raise Error, "Circular dependency detected: #{e.message}"
    end

    # Minimal TSort adapter over the { node => [dependency, ...] } hash
    # built by compile_all.
    class DependencyGraph
      include TSort

      def initialize(deps)
        @deps = deps
      end

      def tsort_each_node(&block)
        @deps.each_key(&block)
      end

      def tsort_each_child(node, &block)
        (@deps[node] || []).each(&block)
      end
    end

    class Parser
      def initialize(tokens, field_map, resolved_calculated = {})
        @tokens = tokens
        @pos = 0
        @field_map = field_map
        @resolved_calculated = resolved_calculated
        @depth = 0
      end

      def parse
        result = parse_additive
        expect(:EOF)
        result
      end

      private

      def parse_additive
        left = parse_multiplicative
        while current_type == :PLUS || current_type == :MINUS
          op = advance[1]
          right = parse_multiplicative
          left = "#{left} #{op} #{right}"
        end
        left
      end

      def parse_multiplicative
        left = parse_unary
        while current_type == :STAR || current_type == :SLASH
          op = advance[1]
          right = parse_unary
          left = "#{left} #{op} #{right}"
        end
        left
      end

      def parse_unary
        if current_type == :MINUS
          advance
          return "-(#{parse_primary})"
        end
        parse_primary
      end

      def parse_primary
        @depth += 1
        raise Error, "Expression too deeply nested" if @depth > 20

        result = case current_type
        when :NUMBER then advance[1]
        when :STRING
                   val = advance[1]
                   "'#{val[1..-2]}'"
        when :LPAREN
                   advance
                   expr = parse_additive
                   expect(:RPAREN)
                   "(#{expr})"
        when :IDENT then parse_identifier
        else raise Error, "Unexpected token: #{current_type}"
        end
        @depth -= 1
        result
      end

      def parse_identifier
        name = advance[1]
        if current_type == :LPAREN && FormulaCompiler::SUPPORTED_FUNCTIONS.include?(name.upcase)
          return parse_function_call(name.upcase)
        end
        resolve_field(name)
      end

      def parse_function_call(func_name)
        advance
        args = []
        unless current_type == :RPAREN
          args << parse_additive
          while current_type == :COMMA
            advance
            args << parse_additive
          end
        end
        expect(:RPAREN)
        "#{func_name}(#{args.join(', ')})"
      end

      def resolve_field(name)
        return "(#{@resolved_calculated[name]})" if @resolved_calculated.key?(name)

        field_info = @field_map[name]
        raise Error, "Unknown field '#{name}'" unless field_info

        if field_info[:calculated] && field_info[:formula]
          schema_as_array = @field_map.values.map { |f| { "name_slug" => f[:slug], "html_type" => f[:html_type], "type" => f[:type], "formula" => f[:formula] } }
          return "(#{FormulaCompiler.compile(field_info[:formula], schema_as_array, @resolved_calculated)})"
        end

        if FormulaCompiler::NUMERIC_HTML_TYPES.include?(field_info[:html_type])
          "CAST(json_extract(entity_entries.data, '$.#{name}') AS NUMERIC)"
        else
          "json_extract(entity_entries.data, '$.#{name}')"
        end
      end

      def current_type = @tokens[@pos]&.first
      def advance
        token = @tokens[@pos]
        @pos += 1
        token
      end
      def expect(type)
        raise Error, "Expected #{type}, got #{current_type}" unless current_type == type
        advance
      end
    end
  end
end
