# frozen_string_literal: true

module Operations
  class SchemaLint
    # Only keywords whose values are schemas are walked. `examples`, `enum`,
    # `const`, `default` and `x-*` hold instance data, which may well contain
    # keys such as `type` that would otherwise read as schemas. `if` is a test,
    # not documentation, so it is never linted.
    SCHEMA_MAP_KEYWORDS = %w[properties patternProperties $defs dependentSchemas].freeze
    SCHEMA_KEYWORDS = %w[items additionalProperties unevaluatedProperties unevaluatedItems contains not propertyNames then else].freeze
    SCHEMA_LIST_KEYWORDS = %w[allOf anyOf oneOf prefixItems].freeze
    CONDITIONAL_BRANCHES = %w[then else].freeze

    def self.call(operation_class, context)
      new(operation_class, context).call
    end

    def initialize(operation_class, context)
      @operation_class = operation_class
      @context = context
    end

    def call
      problems = []
      problems << "title is missing" if @operation_class.title.blank?
      problems << "summary is missing" if @operation_class.summary.blank?
      problems << "schema description is missing" if document["description"].blank?

      each_schema(document, "#", documented: true) do |node, path, documented|
        lint_node(node, path, documented, problems)
      end

      lint_examples(problems)
      lint_projection(problems)
      problems
    end

    private

    def document
      @document ||= @operation_class.input_schema(@context).document
    end

    # `documented` marks the positions a reader lands on: the root, each
    # named property, each `$defs` entry and array items. Combinator
    # branches inherit the description of the schema that holds them.
    def lint_node(node, path, documented, problems)
      if documented && node["description"].blank?
        problems << "#{path} is missing a description"
      end

      if node["enum"].is_a?(Array)
        descriptions = node["x-enum-descriptions"] || {}
        node["enum"].each do |value|
          next if value.nil?
          next if descriptions.key?(value) || descriptions.key?(value.to_s)

          problems << "#{path} enum value #{value.inspect} is missing x-enum-descriptions"
        end
      end

      if node["allOf"].is_a?(Array)
        node["allOf"].each_with_index do |item, index|
          next unless item.is_a?(Hash) && conditional?(item) && item["description"].blank?

          problems << "#{path}/allOf/#{index} conditional is missing a description"
        end
      end

      if object_schema?(node) && node["additionalProperties"] != false &&
         CONDITIONAL_BRANCHES.exclude?(path.split("/").last)
        problems << "#{path} object is missing additionalProperties: false"
      end
    end

    def lint_examples(problems)
      examples = document["examples"]
      return unless examples.is_a?(Array)

      schema = Schema.new(@operation_class, context: @context)
      examples.each_with_index do |example, index|
        violations, = schema.validate(example)
        problems << "# examples[#{index}] is invalid" if violations.any?
      end
    end

    def lint_projection(problems)
      SchemaProjection.call(document)
    rescue SchemaProjection::TooLarge => e
      problems << e.message
    end

    def each_schema(node, path, documented:, &block)
      return unless node.is_a?(Hash)

      yield node, path, documented
      SCHEMA_MAP_KEYWORDS.each do |keyword|
        next unless node[keyword].is_a?(Hash)

        node[keyword].each do |name, child|
          each_schema(child, "#{path}/#{keyword}/#{Pointer.escape(name)}", documented: true, &block)
        end
      end
      SCHEMA_KEYWORDS.each do |keyword|
        next unless node[keyword].is_a?(Hash)

        each_schema(node[keyword], "#{path}/#{keyword}", documented: keyword == "items", &block)
      end
      SCHEMA_LIST_KEYWORDS.each do |keyword|
        next unless node[keyword].is_a?(Array)

        node[keyword].each_with_index do |child, index|
          each_schema(child, "#{path}/#{keyword}/#{index}", documented: keyword == "prefixItems", &block)
        end
      end
    end

    def object_schema?(node)
      type = node["type"]
      type == "object" || (type.is_a?(Array) && type.include?("object")) || node.key?("properties")
    end

    def conditional?(node)
      node.key?("if") || node.key?("then") || node.key?("else")
    end
  end
end
