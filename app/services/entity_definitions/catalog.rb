# frozen_string_literal: true

module EntityDefinitions
  # Snapshot of live customer-owned entity definitions for the assistant
  # prompt. Omits identity keys the persist path must not accept (id, shared,
  # status, bridge ids) so a catalog echo can update by name.
  class Catalog
    def self.for_customer(customer_id)
      new(customer_id).documents
    end

    def self.document_for(customer_id, name)
      new(customer_id).document_named(name)
    end

    def initialize(customer_id)
      @customer_id = customer_id
    end

    def documents
      scope.map { |entity| document(entity) }
    end

    def document_named(name)
      entity = scope.find_by(name: name)
      entity && document(entity)
    end

    private

    def scope
      Entity.where(customer_id: @customer_id)
            .non_bridge
            .by_name
            .includes(current_version: :content)
    end

    def document(entity)
      {
        "name" => entity.name,
        "display_label" => entity.display_label,
        "extended_model" => entity.extended_model,
        "icon" => entity.icon,
        "color" => entity.color,
        "description" => entity.description,
        "property_schema" => property_schema(entity),
        "attribute_groups" => entity.attribute_groups_json || [],
        "associations" => associations_document(entity),
        "default_properties" => entity.default_properties_json || {},
        "referenced_template" => entity.referenced_template
      }
    end

    def property_schema(entity)
      Array(entity.property_schema_json).filter_map do |attr|
        next if attr["type"].to_s == Entity::ENTITY_REFERENCE_TYPE

        row = attr.except("entity_id")
        row = row.merge("config" => computed_config(entity, row["config"])) if row["type"].to_s == Entity::COMPUTED_TYPE
        row = row.merge("config" => option_source_config(row["config"])) if row["config"].is_a?(Hash)
        row
      end
    end

    # A choice list bound to another entity's entries is echoed by name;
    # Persist turns the name back into the id, which keeps an echo lossless.
    def option_source_config(config)
      ChoiceList.to_prompt(config, names_by_id: entity_names)
    end

    def entity_names
      @entity_names ||= ChoiceList.names_by_id(@customer_id)
    end

    def computed_config(entity, config)
      config = (config || {}).stringify_keys
      if config["target_entity_name"].blank? && config["bridge_entity_id"].present?
        config["target_entity_name"] = related_entity_name(entity, config["bridge_entity_id"])
      end
      config.except("bridge_entity_id")
    end

    # Source direction: this entity owns the association. Target direction:
    # the related entity owns it, so recover the name from the bridge's
    # source participant (schema[0]).
    def related_entity_name(entity, bridge_id)
      assoc = Array(entity.associations_list).find { |row| row["bridge_entity_id"].to_s == bridge_id.to_s }
      return assoc["target_entity_name"] if assoc

      bridge = Entity.where(customer_id: @customer_id, category: :bridge).find_by(id: bridge_id.to_i)
      return unless bridge

      source_ref = Array(bridge.property_schema_json)[0]
      return unless source_ref.is_a?(Hash)

      Entity.where(customer_id: @customer_id).find_by(id: source_ref["entity_id"].to_i)&.name || source_ref["name"]
    end

    def associations_document(entity)
      Array(entity.associations_list).map do |assoc|
        extras = Array(assoc["additional_attributes"]).reject { |attr| attr["type"].to_s == Entity::ENTITY_REFERENCE_TYPE }
        {
          "associated_entity_name" => assoc["target_entity_name"],
          "display_field" => assoc["display_field"],
          "display_field_label" => assoc["display_field_label"],
          "additional_attributes" => extras
        }
      end
    end
  end
end
