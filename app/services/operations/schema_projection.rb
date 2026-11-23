# frozen_string_literal: true

module Operations
  class SchemaProjection
    class TooLarge < StandardError; end

    DROPPED_KEYS = %w[$schema $id $defs $comment examples].freeze
    CONDITIONAL_KEYS = %w[if then else allOf not dependentRequired].freeze
    DEFAULT_BUDGET = 32_000

    def self.call(document, budget: DEFAULT_BUDGET)
      new(document, budget: budget).call
    end

    def initialize(document, budget:)
      @document = document
      @budget = budget
    end

    def call
      defs = (@document["$defs"] || {}).deep_dup
      projected = project(deep_copy(@document), defs, [])
      payload = JSON.generate(projected)
      raise TooLarge, "projected schema is #{payload.bytesize} bytes (budget #{@budget})" if payload.bytesize > @budget

      projected
    end

    private

    def project(node, defs, stack)
      case node
      when Array
        node.map { |item| project(item, defs, stack) }
      when Hash
        inlined = inline_ref(node, defs, stack)
        return project(inlined, defs, stack) if inlined != node && inlined.is_a?(Hash) && inlined.key?("$ref") == false && node.key?("$ref")

        node = inlined
        fold_enum_descriptions!(node)
        fold_conditionals!(node)
        node["anyOf"] = node.delete("oneOf") if node.key?("oneOf")
        cleaned = node.each_with_object({}) do |(key, value), acc|
          next if drop_key?(key)

          acc[key] = project(value, defs, stack)
        end
        cleaned
      else
        node
      end
    end

    def inline_ref(node, defs, stack)
      ref = node["$ref"]
      return node unless ref.is_a?(String) && ref.start_with?("#/$defs/")

      name = ref.delete_prefix("#/$defs/")
      return node.except("$ref") if stack.include?(name)

      target = defs[name]
      return node unless target.is_a?(Hash)

      merged = deep_copy(target).merge(node.except("$ref"))
      inline_ref(merged, defs, stack + [name])
    end

    def fold_enum_descriptions!(node)
      descriptions = node["x-enum-descriptions"]
      return unless descriptions.is_a?(Hash) && descriptions.any?

      allowed = descriptions.map { |value, text| "`#{value}` — #{text.to_s.strip.chomp('.')}" }.join("; ")
      suffix = "Allowed values: #{allowed}."
      node["description"] = [node["description"].presence, suffix].compact.join(" ")
    end

    def fold_conditionals!(node)
      extras = []
      if node["allOf"].is_a?(Array)
        node["allOf"].each do |item|
          next unless item.is_a?(Hash)

          extras << item["description"] if item["description"].present?
          merge_schema!(node, item) unless conditional?(item)
        end
      end
      %w[if then else not dependentRequired].each do |key|
        extras.concat(descriptions_of(node[key])) if node.key?(key)
      end
      CONDITIONAL_KEYS.each { |key| node.delete(key) }
      extras = extras.compact.reject(&:blank?)
      return if extras.empty?

      node["description"] = [node["description"].presence, *extras].compact.join(" ")
    end

    def merge_schema!(parent, child)
      if child["properties"].is_a?(Hash)
        parent["properties"] = (parent["properties"] || {}).merge(child["properties"])
      end
      if child["required"].is_a?(Array)
        parent["required"] = Array(parent["required"]) | child["required"]
      end
      child.each do |key, value|
        next if %w[properties required description if then else allOf not dependentRequired].include?(key)

        parent[key] = value unless parent.key?(key)
      end
    end

    def conditional?(node)
      node.key?("if") || node.key?("then") || node.key?("else")
    end

    def descriptions_of(value)
      case value
      when Hash then [value["description"]]
      when Array then value.grep(Hash).map { |item| item["description"] }
      else []
      end
    end

    def drop_key?(key)
      key.start_with?("x-") || DROPPED_KEYS.include?(key)
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end
end
