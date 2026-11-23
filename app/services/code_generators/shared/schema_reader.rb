# frozen_string_literal: true

module CodeGenerators
  module Shared
    module SchemaReader
      ELEMENT_TYPE_KEYS = %w[start end process decision loop subflow].freeze

      ROLE_UI_TYPE = {
        enum: :select,
        integer: :number,
        decimal: :number,
        mapping: :key_value_list,
        flag: :checkbox,
        list: :list,
        conditions: :conditions,
        template: :textarea
      }.freeze

      module_function

      def read(action_name)
        key = action_name.to_s
        klass = if ELEMENT_TYPE_KEYS.include?(key)
          GeneratorRegistry.find_element_type(key)
        else
          GeneratorRegistry.find_step_action(key)
        end
        schema = klass&._config_schema
        return [] unless schema

        schema.fields.map { |field| declared_to_ui(field) }
      end

      def each_enum_branch(action_name)
        read(action_name).each do |field|
          next unless field[:type] == :select
          options = field[:options]
          next unless options.is_a?(Array)
          options.each do |option|
            value = option.is_a?(Hash) ? (option["value"] || option[:value]) : option
            next if value.nil?
            yield(field[:key], value)
          end
        end
      end

      def declared_to_ui(field)
        values = Array(field.options[:values])
        {
          key: field.name,
          type: ROLE_UI_TYPE.fetch(field.role, :text),
          role: field.role,
          required: field.options[:required] == true,
          default: field.options[:default],
          min: field.options[:min],
          max: field.options[:max],
          options: values.map { |value| { "value" => value.to_s, "label" => value.to_s } },
          visibleWhen: visible_when_for(field)
        }.compact
      end

      def visible_when_for(field)
        cond = Array(field.conditions).find { |item| item[:type] == :visible } ||
               Array(field.conditions).find { |item| item[:type] == :requires }
        raw = cond ? cond[:when] : field.options[:visible]
        return nil unless raw.is_a?(Hash) && raw.any?

        name, values = raw.first
        { "field" => name.to_s, "values" => Array(values).map(&:to_s) }
      end
    end
  end
end
