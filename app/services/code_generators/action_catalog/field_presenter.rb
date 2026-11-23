# frozen_string_literal: true

module CodeGenerators
  class ActionCatalog
    # Builds one A4 field hash from a ported DeclaredField.
    class FieldPresenter
      ROLE_CONTROLS = {
        input: { "control" => "text", "variablePicker" => true },
        output: { "control" => "text", "variablePicker" => false },
        expression: { "control" => "code" },
        literal: { "control" => "text" },
        template: { "control" => "textarea", "multiline" => true },
        enum: { "control" => "select" },
        flag: { "control" => "toggle" },
        integer: { "control" => "number" },
        decimal: { "control" => "number" },
        list: { "control" => "list" },
        mapping: { "control" => "mapping" },
        conditions: { "control" => "conditions" },
        entity_attribute: { "control" => "attribute_picker" },
        reference: { "control" => "reference_picker" },
        localized_text: { "control" => "localized_text" }
      }.freeze

      def self.option_key(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_")
      end

      def self.none_label(locale, i18n_prefix: "flowchart_actions")
        key = "#{i18n_prefix}.shared.none"
        I18n.exists?(key, locale, fallback: false) ? I18n.t(key, locale: locale) : "None"
      end

      def self.lookup(action_key, field_name, part, locale:, i18n_prefix: "flowchart_actions")
        action = "#{i18n_prefix}.#{action_key}.fields.#{field_name}.#{part}"
        shared = "#{i18n_prefix}.shared.fields.#{field_name}.#{part}"
        if I18n.exists?(action, locale, fallback: false)
          I18n.t(action, locale: locale)
        elsif I18n.exists?(shared, locale, fallback: false)
          I18n.t(shared, locale: locale)
        end
      end

      def self.option_label(action_key, field_name, value, locale:, i18n_prefix: "flowchart_actions")
        key = "#{i18n_prefix}.#{action_key}.fields.#{field_name}.options.#{option_key(value)}"
        I18n.exists?(key, locale, fallback: false) ? I18n.t(key, locale: locale) : value.to_s
      end

      def self.from_declared(action_key, field, locale:, i18n_prefix: "flowchart_actions")
        role = field.role
        mapping = ROLE_CONTROLS.fetch(role)
        options = field.options
        multiline = options[:multiline] == true || mapping["multiline"] == true
        control = if role == :literal && multiline
          "textarea"
        else
          mapping["control"]
        end
        visible = condition_when(field, :visible) || stringify_when(options[:visible])
        required_when = condition_when(field, :requires)
        required = options[:required] == true
        enum_options = enum_options_for(
          action_key, field, required: required, locale: locale, i18n_prefix: i18n_prefix
        )

        blank.merge(
          "name" => field.name,
          "role" => role.to_s,
          "control" => control,
          "label" => lookup(action_key, field.name, "label", locale: locale, i18n_prefix: i18n_prefix),
          "help" => lookup(action_key, field.name, "help", locale: locale, i18n_prefix: i18n_prefix),
          "placeholder" => placeholder_for(action_key, field, locale: locale, i18n_prefix: i18n_prefix),
          "default" => options.key?(:default) ? options[:default] : nil,
          "required" => required,
          "group" => (options[:group] || :main).to_s,
          "options" => enum_options,
          "min" => options[:min],
          "max" => options[:max],
          "visibleWhen" => visible,
          "requiredWhen" => required_when,
          "variablePicker" => mapping["variablePicker"] == true,
          "source" => options[:source]&.to_s,
          "itemRole" => options[:item]&.to_s,
          "keyRole" => options[:key]&.to_s,
          "valueRole" => options[:value]&.to_s,
          "multiline" => multiline,
          "maxLength" => options[:max_length]
        )
      end

      def self.blank
        {
          "label" => nil,
          "help" => nil,
          "placeholder" => nil,
          "default" => nil,
          "required" => false,
          "group" => "main",
          "options" => [],
          "min" => nil,
          "max" => nil,
          "visibleWhen" => nil,
          "requiredWhen" => nil,
          "variablePicker" => false,
          "source" => nil,
          "itemRole" => nil,
          "keyRole" => nil,
          "valueRole" => nil,
          "multiline" => false,
          "maxLength" => nil
        }
      end

      def self.enum_options_for(action_key, field, required:, locale:, i18n_prefix: "flowchart_actions")
        return [] unless field.role == :enum

        values = Array(field.options[:values])
        rows = values.map do |value|
          {
            "value" => value,
            "label" => option_label(action_key, field.name, value, locale: locale, i18n_prefix: i18n_prefix)
          }
        end
        return rows if required

        [{ "value" => "", "label" => none_label(locale, i18n_prefix: i18n_prefix) }] + rows
      end

      def self.placeholder_for(action_key, field, locale:, i18n_prefix: "flowchart_actions")
        return nil unless field.options[:placeholder]

        lookup(action_key, field.name, "placeholder", locale: locale, i18n_prefix: i18n_prefix)
      end

      def self.condition_when(field, type)
        matches = field.conditions.select { |condition| condition[:type] == type }
        return nil if matches.empty?

        stringify_when(matches.first[:when])
      end

      def self.stringify_when(hash)
        return nil if hash.blank?

        hash.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end
      end
    end
  end
end
