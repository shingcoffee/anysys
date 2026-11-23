# frozen_string_literal: true

module Entities
  # The value a new record of an entity starts with for an attribute: the
  # definition's stored default, else the options flagged default — all of
  # them for a multi-select, the one for a single choice (several flags on a
  # single choice pick none).
  module AttributeDefaults
    SINGLE_CHOICE_TYPES = %w[select radio].freeze

    module_function

    def call(entity, slugs)
      stored = entity.default_properties_json.to_h
      attributes = Array(entity.property_schema_json).grep(Hash).index_by { |attribute| attribute["name_slug"].to_s }
      slugs.map(&:to_s).each_with_object({}) do |slug, out|
        next out[slug] = stored[slug] if stored.key?(slug)

        value = choice_default(attributes[slug])
        out[slug] = value unless value.nil?
      end
    end

    def flagged(attribute)
      Array(attribute.dig("config", "options"))
        .select { |option| option.is_a?(Hash) && option["default"] == true }
        .map { |option| option["value"] }
    end

    def choice_default(attribute)
      return unless attribute

      values = flagged(attribute)
      if attribute["html_type"] == "multi-select"
        values.presence
      elsif SINGLE_CHOICE_TYPES.include?(attribute["html_type"]) && values.one?
        values.first
      end
    end
    private_class_method :choice_default
  end
end
