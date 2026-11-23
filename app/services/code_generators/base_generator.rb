# frozen_string_literal: true

require "prism"
require_relative "generator_interface"
require_relative "shared/ctx_reader"
require_relative "shared/config_field_reader"
require_relative "shared/identifier_sanitizer"
require_relative "shared/expression_safety"
require_relative "shared/ruby_literal"

module CodeGenerators
  class BaseGenerator
    include GeneratorInterface
    include Shared::CtxReader
    include Shared::ConfigFieldReader
    include Shared::IdentifierSanitizer
    include Shared::ExpressionSafety

    # Expressions of these shapes bind tighter than any operator, so they are
    # spliced without wrapping parentheses.
    PRIMARY_NODES = [
      Prism::StringNode, Prism::InterpolatedStringNode, Prism::SymbolNode, Prism::InterpolatedSymbolNode,
      Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
      Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::SelfNode, Prism::ArrayNode,
      Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::LocalVariableReadNode,
      Prism::InstanceVariableReadNode, Prism::ParenthesesNode, Prism::RegularExpressionNode,
      Prism::LambdaNode
    ].freeze

    LIQUID_MARKUP = /\{\{|\{%/

    def initialize(element, context)
      @element = element
      @context = context
      @config = extract_config
    end

    def value(name)
      self.class._config_schema.value(@config, name)
    end

    def read(name)
      field = schema_field!(name)
      emit_role(field, value(name))
    rescue ArgumentError, TypeError
      raise_unsafe_value!(name)
    end

    def literal(value)
      Shared::RubyLiteral.emit(value)
    end

    def assign(output_field, expr)
      key = value(output_field)
      raise_unsafe_value!(output_field) unless safe_ident?(key)

      "ctx[:#{key}] = #{expr}"
    end

    def fail_with(code, field: nil, **details)
      unless_expr = details.delete(:unless)
      args = [":#{code}"]
      args << "field: :#{field}" if field
      details.each { |key, source| args << "#{key}: #{source}" }
      line = "return FlowchartRuntime::Step.fail(ctx, #{args.join(', ')})"
      unless_expr ? "#{line} unless #{unless_expr}" : line
    end

    def attempt(code, *error_classes)
      lines = Array(yield).flatten.compact
      classes = error_classes.map { |klass| klass.is_a?(Module) ? klass.name : klass.to_s }.join(", ")
      header = classes.empty? ? ":#{code}" : ":#{code}, #{classes}"
      <<~RUBY.chomp
        FlowchartRuntime::Step.attempt(ctx, #{header}) do
        #{lines.join("\n").indent(2)}
        end
      RUBY
    end

    def body(*lines)
      lines.flatten.compact.join("\n")
    end

    protected

    attr_reader :element, :context, :config

    private

    def extract_config
      raw = if self.class.generator_kind == :element_type
              element.fetch("properties", {})
      else
              element.fetch("config", {})
      end
      (raw || {}).with_indifferent_access
    end

    def schema_field!(name)
      schema = self.class._config_schema
      field = schema&.find_declared(name)
      raise ArgumentError, "undeclared config field #{name.inspect}" unless field

      field
    end

    def emit_role(field, raw)
      case field.role
      when :input then emit_input_path(field, raw)
      when :output then safe_ident?(raw) ? raw.to_s : raise_unsafe_value!(field.name)
      when :expression then emit_expression(raw)
      when :literal, :enum, :entity_attribute, :reference then raw.to_s.inspect
      when :template then emit_template(raw)
      when :flag then raw ? "true" : "false"
      when :integer then Integer(raw).to_s
      when :decimal then Float(raw).to_s
      when :list then literal(Array(raw).map(&:to_s))
      when :mapping then emit_mapping(raw)
      else literal(raw)
      end
    end

    def emit_input_path(field, path)
      root, *rest = path.to_s.split(".", -1)
      return "nil" if root.nil?
      raise_unsafe_value!(field.name) unless safe_ident?(root) && rest.all? { |s| safe_ident?(s) || s.match?(/\A\d+\z/) }
      return "ctx[:#{root}]" if rest.empty?

      keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
      "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
    end

    def emit_expression(raw)
      source = raw.to_s.strip
      primary_expression?(source) ? source : "(#{source})"
    end

    def primary_expression?(source)
      result = Prism.parse(source)
      statements = result.value.statements.body
      result.success? && statements.size == 1 && primary_node?(statements.first)
    end

    def primary_node?(node)
      return primary_call?(node) if node.is_a?(Prism::CallNode)
      return false if node.respond_to?(:opening_loc) && node.opening_loc&.slice&.start_with?("<<")

      PRIMARY_NODES.any? { |klass| node.is_a?(klass) }
    end

    # `a.b`, `a.b(c)`, `a[b]`, `foo` and `items.map { … }` are primary;
    # operators (`a + b`, `!a`) and paren-less commands (`foo bar`) are not.
    def primary_call?(node)
      return false if node.block.is_a?(Prism::BlockNode) && node.block.opening_loc.slice != "{"
      return node.opening_loc&.slice == "[" if node.name == :[]
      return false if node.receiver && node.call_operator_loc.nil?

      node.arguments.nil? || node.opening_loc&.slice == "("
    end

    # Plain text renders to itself, so only Liquid markup needs the runtime.
    def emit_template(raw)
      text = raw.to_s
      return text.inspect unless text.match?(LIQUID_MARKUP)

      "FlowchartRuntime::Template.render(#{text.inspect}, ctx)"
    end

    def raise_unsafe_value!(name)
      raise CodeGenerators::GeneratorError,
        I18n.t("maint_core.flowcharts.generator_unsafe_value", field: name, action: self.class.generator_name)
    end

    def emit_mapping(raw)
      pairs = Array(raw).filter_map do |row|
        next unless row.is_a?(Hash)

        key = row["key"] || row[:key]
        next if key.nil?

        [key.to_s, row["value"] || row[:value]]
      end
      literal(pairs.to_h)
    end
  end
end
