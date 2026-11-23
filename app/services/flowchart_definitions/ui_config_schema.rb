# frozen_string_literal: true

module FlowchartDefinitions
  # Step-action defaults come from ActionCatalog (ported generator schemas).
  # Element defaults come from each element's Ruby config_schema, honouring
  # visibility so hidden-mode values are not seeded.
  module UiConfigSchema
    ELEMENT_OWNED_KEYS = %w[label steps].freeze
    ELEMENT_TYPES = %w[start end process decision loop subflow].freeze

    module_function

    def fields_for(name)
      catalog_fields(name) || element_fields_for(name)
    end

    def element_fields_for(name)
      generator = CodeGenerators::GeneratorRegistry.find_element_type(name)
      schema = generator&._config_schema
      if schema
        stringify_fields(
          schema.fields.map do |field|
            CodeGenerators::ActionCatalog::FieldPresenter.from_declared(
              generator.generator_name,
              field,
              locale: "en",
              i18n_prefix: "flowchart_elements"
            )
          end
        )
      else
        stringify_fields(CodeGenerators::Shared::SchemaReader.read(name))
      end
    end

    def defaults_for(name)
      if ELEMENT_TYPES.include?(name.to_s)
        element_defaults(name).except(*ELEMENT_OWNED_KEYS)
      else
        defaults_from(fields_for(name)).except(*ELEMENT_OWNED_KEYS)
      end
    end

    def defaults_from(fields)
      stringify_fields(fields).each_with_object({}) do |field, acc|
        key = field["name"].presence || field["key"].to_s
        next if key.empty?

        value = if field.key?("default")
          field["default"]
        else
          field["defaultValue"]
        end
        acc[key] = value unless value.nil?
      end
    end

    def stringify_fields(fields)
      Array(fields).map { |field| stringify_value(field) }
    end

    def reset!
      @action_fields = nil
    end

    def stringify_value(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), acc| acc[key.to_s] = stringify_value(item) }
      when Array
        value.map { |item| stringify_value(item) }
      when Symbol
        value.to_s
      else
        value
      end
    end

    def catalog_fields(name)
      action_fields[name.to_s]
    end

    def action_fields
      @action_fields ||= begin
        Assistant::SchemaGenerator.action_index.each_with_object({}) do |(key, action), acc|
          acc[key] = stringify_fields(action["fields"])
        end
      end
    end

    def element_defaults(name)
      generator = CodeGenerators::GeneratorRegistry.find_element_type(name)
      schema = generator&._config_schema
      return {} unless schema

      stringify_value(schema.visible_defaults)
    end
  end
end
