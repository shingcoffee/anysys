# frozen_string_literal: true

require "json_schemer"

module Websites
  # The editor's field descriptors are also the persistence schema. JSONSchemer
  # checks nested types, unknown keys and list cardinality before decoration can
  # coerce malformed input into an apparently valid section.
  module PropSchema
    module_function

    def valid?(type, props)
      return false unless props.is_a?(Hash) && SectionKit.known?(type)

      validation_errors(type, props).empty?
    end

    def validation_errors(type, props)
      value = props.is_a?(Hash) ? props.deep_stringify_keys : props
      schema = object_schema(SectionFields.full_schema_for(type), SectionStyles::PROP => SectionStyles.json_schema(type))
      JSONSchemer.schema(schema).validate(value).to_a
    end

    def object_schema(fields, extra_properties = {})
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => fields.to_h { |field| [field[:key], field_schema(field)] }.merge(extra_properties),
        "required" => fields.filter_map { |field| field[:key] if field[:kind] == :array && field[:min].positive? }
      }
    end

    def field_schema(field)
      case field[:kind]
      when :array
        {
          "type" => "array", "minItems" => field[:min], "maxItems" => field[:max],
          "items" => object_schema(field[:item_fields])
        }
      else
        { "type" => ["string", "null"] }
      end
    end
  end
end
