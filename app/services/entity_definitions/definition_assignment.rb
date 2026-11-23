# frozen_string_literal: true

module EntityDefinitions
  # The in-memory half of writing a definition: everything Persist does to an
  # Entity record before it is saved.
  #
  # Persist writes whole documents, so the only honest way to say what a
  # document would change is to perform the assignment and look at the result.
  # The assistant's change plan does exactly that — on an unsaved copy, then
  # diffing Entity#definition_snapshot before against after — and that is only
  # sound because there is ONE implementation of the assignment. A list of
  # "interesting keys" maintained next to the writer goes stale the day a key
  # is added to the schema, and a key nobody enumerated is a change nobody
  # reviews.
  #
  # Everything here is pure record mutation. The host supplies the parts that
  # are not:
  #
  #   #tenant_id            — the customer these definitions belong to
  #   #fail!(messages)      — how a definition that cannot be applied is raised
  #   #resolve_entity(name) — name → entity record, however the host looks up
  module DefinitionAssignment
    include AttributeMerge

    # What the first pass could not finish. Computed attributes need every
    # association in the batch to exist before their bridge can be named, so
    # they are held back and merged in a second pass.
    Body = Struct.new(:computed_attributes, :incoming_groups, :computed_slots, keyword_init: true)

    def assign_identity(record, definition, name)
      record.name = name
      record.display_label = definition["display_label"].presence || name
      return unless definition.key?("extended_model")

      class_name = definition["extended_model"].to_s.presence
      validate_extended_model!(class_name) if class_name
      record.extended_model = class_name
    end

    # Refusing a base model the tenant may not extend is the writer's job.
    # The change plan overrides this to a no-op: its job is to say what the
    # document asks for, and a document asking for something impossible is
    # still better read as a row than as "cannot be planned".
    def validate_extended_model!(class_name)
      return if allowed_extended_model?(class_name)

      fail!(I18n.t("ai_assistant.assistant.apply_errors.invalid_extended_model", name: class_name))
    end

    def allowed_extended_model?(class_name)
      ExtendableModelRegistry.for_customer(tenant_id).any? { |model| model[:class_name] == class_name }
    end

    def assign_body(record, definition, replace: false)
      record.icon = definition["icon"] if definition.key?("icon")
      record.color = definition["color"] if definition.key?("color")
      record.description = definition["description"] if definition.key?("description")
      record.referenced_template = definition["referenced_template"] if definition.key?("referenced_template")
      record.default_properties_json = definition["default_properties"] if definition.key?("default_properties")

      incoming_groups = definition.key?("attribute_groups") ? definition["attribute_groups"] : nil
      computed_attributes = nil
      computed_slots = nil
      if definition.key?("property_schema")
        input_attributes, computed_attributes = partition_attributes(definition["property_schema"])
        computed_slots = computed_slots_for(definition["property_schema"])
        record.property_schema_json = if replace
          input_attributes
        else
          merge_attributes(record.property_schema_json, input_attributes)
        end
      end

      body = Body.new(
        computed_attributes: computed_attributes,
        incoming_groups: incoming_groups,
        computed_slots: computed_slots
      )
      return body unless definition.key?("property_schema") || definition.key?("attribute_groups")

      apply_grouping!(record, incoming_groups, replace: replace)
      body
    end

    def apply_grouping!(record, incoming_groups, replace: false)
      grouped = AttributeGrouper.call(
        attributes: record.property_schema_json,
        existing_groups: replace ? [] : record.attribute_groups_json,
        incoming_groups: incoming_groups
      )
      record.attribute_groups_json = grouped.groups
      record.property_schema_json = grouped.attributes
    end

    def partition_attributes(attrs)
      list = Array(attrs)
      computed_attrs = list.select { |attr| computed_attribute?(attr) }
      input_attrs = list.reject { |attr| computed_attribute?(attr) }
      [input_attrs, computed_attrs]
    end

    def computed_slots_for(attrs)
      Array(attrs).each_with_index.filter_map do |attr, index|
        next unless computed_attribute?(attr)

        { index: index, attribute: attr }
      end
    end

    def computed_attribute?(attr)
      attr.is_a?(Hash) && attr["type"].to_s == Entity::COMPUTED_TYPE
    end

    # Re-insert resolved computed attributes at the indexes they held in the
    # authored list. Insert in ascending index order so later slots land
    # after earlier ones have shifted the array.
    def reinsert_computed(input_attributes, resolved, slots)
      result = Array(input_attributes).dup
      Array(slots).zip(Array(resolved)).sort_by { |slot, _attr| slot.fetch(:index) }.each do |slot, attr|
        result.insert(slot.fetch(:index), attr)
      end
      result
    end

    # The authored association list with every entity name resolved to an id.
    # Replaces the stored list wholesale — an association the document leaves
    # out is an association that goes away.
    def stored_associations(record, associations)
      Array(associations).map do |assoc|
        target_name = assoc["associated_entity_name"].to_s.strip
        fail!(I18n.t("maint_core.errors.validations.association_missing_display_field", target_name: target_name.presence || "?")) if assoc["display_field"].to_s.strip.blank? || assoc["display_field_label"].to_s.strip.blank?
        target = resolve_entity(target_name)
        fail!(I18n.t("ai_assistant.assistant.apply_errors.target_not_found", name: target_name)) if target.nil?
        # `target.id.present?` matters: a target that does not exist yet has no
        # id, and neither does an unsaved record, so comparing the two raw
        # would read "nil == nil" as an entity pointing at itself.
        if target.id.present? && target.id == record.id
          fail!(I18n.t("maint_core.errors.validations.association_self_reference"))
        end

        {
          "target_entity_id" => target.id,
          "target_entity_name" => target.name,
          "display_field" => assoc["display_field"].to_s.strip,
          "display_field_label" => assoc["display_field_label"].to_s.strip,
          "additional_attributes" => Array(assoc["additional_attributes"])
        }
      end
    end

    # sync_bridge_entities! keeps the bridge of an association whose target
    # did not change. Carrying those ids over is what lets an untouched
    # association compare equal, what keeps the record from colliding with
    # its own live bridge on save, and what lets a Computed attribute find
    # the bridge it aggregates through.
    def carry_bridges(existing, assigned)
      previous = Array(existing).grep(Hash).index_by { |row| row["target_entity_name"].to_s }
      assigned.map do |row|
        kept = previous[row["target_entity_name"].to_s]
        kept ? row.merge(kept.slice("bridge_entity_id", "bridge_entity_name", "bridge_entity_display_label")) : row
      end
    end

    def resolve_computed(record, field)
      config = field["config"]
      fail!(I18n.t("maint_core.errors.validations.computed_config_invalid", name: field["name"])) unless config.is_a?(Hash)

      target_name = config["target_entity_name"].to_s.strip
      role = config["bridge_role"].to_s.presence || "source"
      assoc = find_computed_association(record, target_name, role)
      fail!(I18n.t("ai_assistant.assistant.apply_errors.computed_bridge_missing", name: field["name"], target: target_name)) if assoc.nil? || assoc["bridge_entity_id"].blank?

      field.merge(
        "config" => config.except("target_entity_name").merge(
          "bridge_entity_id" => assoc["bridge_entity_id"],
          "bridge_role" => role
        ),
        "readonly" => true,
        "storage" => "computed"
      )
    end

    # `source` — this entity's association to the related entity.
    # `target` — the related entity's association whose target is this entity
    # (the reverse of ComputedOptions.forward_options; see reverse_options).
    def find_computed_association(record, target_name, role)
      if role == "target"
        related = resolve_entity(target_name)
        return nil unless related.respond_to?(:associations_list)

        Array(related.associations_list).find do |row|
          row["target_entity_name"].to_s == record.name ||
            (record.id.present? && row["target_entity_id"].to_s == record.id.to_s)
        end
      else
        Array(record.associations_list).find { |row| row["target_entity_name"].to_s == target_name }
      end
    end
  end
end
