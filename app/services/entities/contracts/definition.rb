# frozen_string_literal: true

module Entities
  module Contracts
    # Structural boundary shared by HTTP definition writes and historical
    # promotion. Entity's existing validators own names, references and other
    # business semantics; this form normalizes only the declared JSON bodies.
    class Definition < Reform::Form
      JSON_TYPES = {
        property_schema: Array, associations: Array, attribute_groups: Array,
        default_properties: Hash, referenced_template: Hash
      }.freeze

      property :definition, virtual: true
      attr_reader :normalized_attributes

      validate :definition_structure

      private

      def definition_structure
        @normalized_attributes = {}
        return invalid_structure unless definition.is_a?(Hash)

        definition.each_pair do |key, raw|
          key = key.to_sym
          next unless JSON_TYPES.key?(key)
          if key == :referenced_template && (raw.nil? || (raw.is_a?(String) && raw.blank?))
            @normalized_attributes[key] = nil
            next
          end

          value = raw.is_a?(String) ? JSON.parse(raw) : raw
          valid = value.is_a?(JSON_TYPES.fetch(key))
          valid &&= value.all? { |item| item.is_a?(Hash) } if value.is_a?(Array)
          if valid && key == :property_schema
            valid = value.all? { |field| attribute_shape?(field) }
          elsif valid && key == :associations
            valid = value.all? do |association|
              extras = association.fetch("additional_attributes", [])
              extras.is_a?(Array) && extras.all? { |field| field.is_a?(Hash) && attribute_shape?(field) }
            end
          elsif valid && key == :referenced_template
            valid = value["key"].is_a?(String) && value["key"].present?
            if value.key?("preview_rows")
              valid &&= value["preview_rows"].is_a?(Array) && value["preview_rows"].all? do |row|
                row.is_a?(Array) && row.all? { |element| element.is_a?(Hash) }
              end
            end
          end
          return invalid_structure unless valid

          @normalized_attributes[key] = value
        end
      rescue JSON::ParserError, TypeError
        invalid_structure
      end

      def attribute_shape?(field)
        return false unless field["name_slug"].is_a?(String) && field["name_slug"].match?(/\A\w+\z/)

        config = field["config"]
        return false unless config.nil? || config.is_a?(Hash)
        if config&.key?("options")
          return false unless config["options"].is_a?(Array) && config["options"].all? { |option| option.is_a?(Hash) }
        end
        validators = field["validators"]
        validators.nil? || (validators.is_a?(Array) && validators.all? do |validator|
          validator.is_a?(String) || (validator.is_a?(Hash) && (validator["config"].nil? || validator["config"].is_a?(Hash)))
        end)
      end

      def invalid_structure
        @normalized_attributes = {}
        errors.add(:base, I18n.t("routes_audit.invalid_definition"))
      end
    end
  end
end
