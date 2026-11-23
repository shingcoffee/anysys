# frozen_string_literal: true

module EntityDefinitions
  # JSON document for one entity definition as seen by the current tenant.
  class Serializer
    def self.call(entity)
      version = entity.resolved_current_version
      {
        id: entity.id,
        name: entity.name,
        display_label: entity.display_label,
        shared: entity.shared?,
        category: entity.category,
        status: entity.status,
        extended_model: entity.extended_model,
        icon: entity.icon,
        color: entity.color,
        description: entity.description,
        property_schema: echo_schema(entity.property_schema_json),
        attribute_groups: entity.attribute_groups_json || [],
        associations: echo_associations(entity.associations_json),
        default_properties: entity.default_properties_json || {},
        referenced_template: entity.referenced_template,
        current_version: version && {
          id: version.id,
          version_number: version.version_number
        }
      }
    end

    def self.echo_schema(schema)
      Array(schema).map { |attr| echo_attribute(attr) }
    end

    def self.echo_attribute(attr)
      return attr unless attr.is_a?(Hash)

      row = attr.dup
      if row["owner"] == true
        row["owner"] = true
      else
        row.delete("owner")
      end
      row
    end

    def self.echo_associations(associations)
      Array(associations).map do |assoc|
        next assoc unless assoc.is_a?(Hash)
        extras = assoc["additional_attributes"]
        next assoc unless extras.is_a?(Array)

        assoc.merge("additional_attributes" => extras.map { |attr| echo_attribute(attr) })
      end
    end
    private_class_method :echo_schema, :echo_attribute, :echo_associations
  end
end
