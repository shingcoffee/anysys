# frozen_string_literal: true

# Manages bridge entity lifecycle for many-to-many associations.
#
# Handles creation, syncing, renaming, cleanup, and deletion of
# bridge entities that link two entities together.
#
# @example
#   class Entity < ApplicationRecord
#     include BridgeEntityManagement
#   end
#
module BridgeEntityManagement
  extend ActiveSupport::Concern

  # Matches non-bridge peers whose head-version definition has an association
  # targeting this entity. Walks the payload's `associations` array with
  # json_each(json_extract(...)) rather than a fragile `LIKE "%...%"` substring
  # scan — correct regardless of whether target_entity_id is stored as an integer
  # or a string, and immune to JSON whitespace.
  TARGET_REFERENCE_SQL = <<~SQL.squish
    EXISTS (
      SELECT 1
      FROM json_each(json_extract(entity_definition_contents.payload, '$.associations')) AS assoc
      WHERE CAST(json_extract(CASE WHEN assoc.type = 'object' THEN assoc.value ELSE '{}' END, '$.target_entity_id') AS TEXT) = ?
    )
  SQL

  included do
    before_save :track_old_associations, if: :will_save_change_to_associations?
    before_save :rename_bridge_entities, if: :name_changed?
  end

  # Create or update bridge entities for all associations.
  # Returns true on success, false if any bridge entity could not be saved.
  # On failure, errors are added to self.errors[:associations].
  def sync_bridge_entities!(persist: true, previous_associations: nil)
    @bridge_sync_errors = []
    @old_associations_before_update = previous_associations if previous_associations

    cleanup_orphaned_bridge_entities!

    if has_associations?
      associations = associations_list
      associations.each { |assoc| sync_single_bridge_entity(assoc) }

      self.associations_json = associations if @bridge_sync_errors.empty?
    end

    if @bridge_sync_errors.any?
      @bridge_sync_errors.each { |msg| errors.add(:associations, msg) }
      return false
    end
    save(validate: false) if has_associations? && persist && persisted?

    true
  end

  # Clean up bridge entities for removed associations
  def cleanup_orphaned_bridge_entities!
    return if new_record?
    return unless @old_associations_before_update

    old_bridge_ids = @old_associations_before_update.map { |a| a["bridge_entity_id"] }.compact
    current_bridge_ids = associations_list.map { |a| a["bridge_entity_id"] }.compact

    orphaned_bridge_ids = old_bridge_ids - current_bridge_ids
    if orphaned_bridge_ids.any?
      Entity.where(id: orphaned_bridge_ids, customer_id: customer_id, category: :bridge)
            .find_each do |bridge|
        next if bridge.soft_delete

        @bridge_sync_errors ||= []
        @bridge_sync_errors << I18n.t("maint_core.errors.validations.bridge_entity_save_failed", errors: bridge.errors.full_messages.join(", "))
      end
    end
  end

  # Refuse to trash an entity that has associations or that other entities reference
  def soft_delete
    if has_active_associations?
      errors.add(:base, I18n.t("maint_core.errors.validations.entity_has_associations"))
      return false
    end

    references = bridge_entity? ? [] : Entities::ReferenceDependents.for_trash(self).references
    if references.any?
      errors.add(:base, I18n.t("maint_core.errors.validations.entity_referenced",
                               fields: Entities::ReferenceDependents.field_paths(references).to_sentence))
      return false
    end

    @forms_taken_offline = 0
    deleted = false
    self.class.transaction(requires_new: true) do
      raise ActiveRecord::Rollback unless delete_bridge_entities!
      # Before the status change: a shared form's validation looks this entity
      # up through Entity.shared, which hides a trashed entity.
      raise ActiveRecord::Rollback unless take_bound_forms_offline!
      raise ActiveRecord::Rollback unless super

      deleted = true
    end
    @forms_taken_offline = 0 unless deleted
    deleted
  end

  # Launched forms bound to this entity that the last successful trash took
  # offline. A shared entity's count covers every tenant's forms.
  def forms_taken_offline
    @forms_taken_offline.to_i
  end

  # Check if this entity has any active associations (as source or target)
  def has_active_associations?
    return false if bridge_entity?
    return true if has_associations?

    # Any other non-bridge entity in the tenant references this entity as a target.
    entities_referencing_as_target.exists?
  end

  # Find all bridge entities related to this entity (as source or target)
  def find_related_bridge_entities
    bridge_ids = associations_list.filter_map { |a| a["bridge_entity_id"] }

    # Reverse side: entities whose head-content associations reference this entity
    # as target. The SQL narrows to real referencers; re-parse to collect bridge ids.
    entities_referencing_as_target.find_each do |entity|
      entity.associations_list.each do |assoc|
        if assoc["target_entity_id"].to_s == id.to_s && assoc["bridge_entity_id"]
          bridge_ids << assoc["bridge_entity_id"]
        end
      end
    end

    scope = Entity.where(id: bridge_ids.uniq, category: :bridge)
    shared? ? scope : scope.where(customer_id: customer_id)
  end

  # Delete all bridge entities related to this entity
  def delete_bridge_entities!
    find_related_bridge_entities.all? do |bridge|
      next true if bridge.soft_delete

      errors.add(:associations, I18n.t("maint_core.errors.validations.bridge_entity_save_failed", errors: bridge.errors.full_messages.join(", ")))
      false
    end
  end

  # Takes every launched form bound to this entity offline, in every tenant.
  # Returns false, with the form's errors on this entity, if one can't be.
  def take_bound_forms_offline!
    return true if bridge_entity?

    forms = Page.for_entity(id).launched.to_a
    forms.each(&:take_offline!)
    @forms_taken_offline = forms.size
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    false
  end

  # Restore bridge entities that were soft-deleted along with this entity.
  # Called automatically when a non-bridge entity is restored from soft-delete.
  def restore_bridge_entities!
    return true if bridge_entity?

    bridge_entity_ids = associations_list.filter_map { |a| a["bridge_entity_id"] }.uniq
    return true if bridge_entity_ids.empty?

    bridges = Entity.with_deleted.where(customer_id: customer_id, category: :bridge).where(id: bridge_entity_ids).to_a
    unless bridges.map { |bridge| bridge.id.to_s }.to_set == bridge_entity_ids.map(&:to_s).to_set
      errors.add(:associations, :invalid)
      return false
    end
    bridges.all? do |bridge|
      next true if bridge.active? || bridge.restore

      errors.add(:associations, I18n.t("maint_core.errors.validations.bridge_entity_save_failed", errors: bridge.errors.full_messages.join(", ")))
      false
    end
  end

  private

  # Non-bridge peers in this tenant, joined to their head-version content so the
  # associations payload can be queried.
  def referencing_entities_scope
    scope = shared? ? Entity.all : Entity.where(customer_id: customer_id)
    scope.where.not(id: id)
          .where.not(category: :bridge)
          .joins(current_version: :content)
  end

  # Peers whose head definition has an association targeting this entity.
  def entities_referencing_as_target
    referencing_entities_scope.where(TARGET_REFERENCE_SQL, id.to_s)
  end

  def sync_single_bridge_entity(assoc)
    target_entity_id = assoc["target_entity_id"]
    target_entity = Entity.where(customer_id: customer_id).or(Entity.shared).find_by(id: target_entity_id)

    unless target_entity
      @bridge_sync_errors << I18n.t("maint_core.errors.validations.bridge_target_entity_missing", target_entity_id: target_entity_id)
      return false
    end

    bridge_name = generate_bridge_name(name, target_entity.name)

    bridge_entity = Entity.with_deleted.where(customer_id: customer_id, category: :bridge)
                          .find_by(id: assoc["bridge_entity_id"])
    if bridge_entity && bridge_entity.name != bridge_name
      schema = bridge_entity.property_schema_json
      participants_match = schema.is_a?(Array) && schema.first(2).all? { |field| field.is_a?(Hash) } &&
                           schema[0]&.fetch("entity_id", nil).to_s == id.to_s &&
                           schema[1]&.fetch("entity_id", nil).to_s == target_entity.id.to_s
      unless participants_match
        @bridge_sync_errors << errors.generate_message(:associations, :invalid)
        return false
      end
    end
    bridge_entity ||= Entity.with_deleted.where(customer_id: customer_id).find_or_initialize_by(name: bridge_name)
    if bridge_entity.persisted? && !bridge_entity.bridge_entity?
      @bridge_sync_errors << errors.generate_message(:associations, :invalid)
      return false
    end

    bridge_entity.assign_attributes(
      name: bridge_name,
      customer: customer,
      description: I18n.t("maint_core.entities.bridge_description", source: display_label, target: target_entity.display_label),
      category: :bridge,
      status: :active
    )

    bridge_entity.property_schema_json = bridge_property_schema(target_entity, assoc)

    if bridge_entity.save
      assoc["bridge_entity_id"] = bridge_entity.id
      assoc["bridge_entity_name"] = bridge_entity.name
      assoc["bridge_entity_display_label"] = bridge_entity.display_label
      true
    else
      @bridge_sync_errors << I18n.t("maint_core.errors.validations.bridge_entity_save_failed", errors: bridge_entity.errors.full_messages.join(", "))
      false
    end
  end

  # Two EntityReference participant fields (this entity + the target) plus any
  # author-defined extra attributes, forming the bridge entity's property schema.
  def bridge_property_schema(target_entity, assoc)
    ref_validators = [{ "type" => "presence" }, { "type" => "numericality_integer" }]
    display_field       = assoc["display_field"].to_s.strip
    display_field_label = assoc["display_field_label"].presence || display_field
    source_slug         = EntityEntry.attribute_slug_for(name)
    target_slug         = EntityEntry.attribute_slug_for(target_entity.name)

    schema = [
      {
        "name"       => display_label,
        "name_slug"  => source_slug,
        "type"       => Entity::ENTITY_REFERENCE_TYPE,
        "html_type"  => "number",
        "entity_id"  => id.to_s,
        "validators" => ref_validators
      },
      {
        "name"       => target_entity.display_label,
        "name_slug"  => target_slug,
        "type"       => Entity::ENTITY_REFERENCE_TYPE,
        "html_type"  => "select",
        "entity_id"  => target_entity.id.to_s,
        "validators" => ref_validators,
        "config"     => {
          "options_source"      => "entity_entries",
          "entity_id"           => target_entity.id.to_s,
          "label_field"         => display_field,
          "display_field_label" => display_field_label
        }
      }
    ]

    schema + (assoc["additional_attributes"] || [])
  end

  def rename_bridge_entities
    return if new_record?
    return if bridge_entity?

    old_name_slug = EntityEntry.attribute_slug_for(name_was)
    new_name_slug = EntityEntry.attribute_slug_for(name)

    find_related_bridge_entities.each do |bridge|
      schema = bridge.property_schema_json || []

      source_attr = schema[0]
      target_attr = schema[1]

      is_source = source_attr && (source_attr["entity_id"].to_s == id.to_s || source_attr["name_slug"] == old_name_slug)
      is_target = target_attr && (target_attr["entity_id"].to_s == id.to_s || target_attr["name_slug"] == old_name_slug)
      next unless is_source || is_target

      matched_attr = is_source ? source_attr : target_attr
      previous_slug = matched_attr["name_slug"].presence || old_name_slug
      other_attr = is_source ? target_attr : source_attr
      other_entity = Entity.find_by(id: other_attr["entity_id"]) if other_attr
      other_name = other_entity&.name || other_attr["name"]

      new_bridge_name = is_source ? generate_bridge_name(name, other_name) : generate_bridge_name(other_name, name)

      bridge.name = new_bridge_name

      bridge.property_schema_json = schema.map do |attr|
        if attr["entity_id"].to_s == id.to_s || attr["name_slug"] == old_name_slug
          attr.merge("name" => display_label, "name_slug" => new_name_slug)
        else
          attr
        end
      end

      if bridge.description
        bridge.description = I18n.t("maint_core.entities.bridge_description", source: display_label, target: other_entity&.display_label || other_attr["name"])
      end

      rewrite_bridge_entry_join_keys(bridge, from: previous_slug, to: new_name_slug)
      bridge.save(validate: false)
    end

    update_associations_with_new_bridge_names
    update_source_entities_associations
  end

  def update_associations_with_new_bridge_names
    return unless has_associations?

    associations = associations_list
    associations.each do |assoc|
      next unless assoc["bridge_entity_id"]

      bridge = Entity.find_by(id: assoc["bridge_entity_id"], customer_id: customer_id)
      if bridge
        assoc["bridge_entity_name"] = bridge.name
        assoc["bridge_entity_display_label"] = bridge.display_label
      end
    end

    self.associations_json = associations
  end

  def update_source_entities_associations
    Entity.where(customer_id: customer_id)
          .where.not(id: id)
          .where.not(category: :bridge)
          .find_each do |source_entity|
      associations = source_entity.associations_list
      changed = false

      associations.each do |assoc|
        if assoc["target_entity_id"] == id
          assoc["target_entity_name"] = display_label

          if assoc["bridge_entity_id"]
            bridge = Entity.find_by(id: assoc["bridge_entity_id"], customer_id: customer_id)
            if bridge
              assoc["bridge_entity_name"] = bridge.name
              assoc["bridge_entity_display_label"] = bridge.display_label
            end
          end

          changed = true
        end
      end

      if changed
        source_entity.associations_json = associations
        source_entity.save(validate: false)
      end
    end
  end

  def generate_bridge_name(name1, name2)
    source_slug = name1.to_s.parameterize(separator: "_")
    target_slug = name2.to_s.parameterize(separator: "_")
    "assoc_#{source_slug}_#{target_slug}"
  end

  # Join slugs live in bridge entry `data` as JSON keys. When the host entity
  # is renamed the schema slug is rewritten; the stored keys must follow or
  # live computed SQL (which reads the current schema) would miss every row.
  def rewrite_bridge_entry_join_keys(bridge, from:, to:)
    return if from.blank? || to.blank? || from == to

    EntityEntry.where(entity_id: bridge.id, customer_id: customer_id).find_each do |entry|
      data = entry.data_json
      next unless data.is_a?(Hash) && data.key?(from)

      # A slug collision (host renamed onto an existing additional-attribute
      # slug) would otherwise destroy the colliding value. Leave the row alone
      # and let the duplicate-slug validation surface the conflict instead.
      next if data.key?(to)

      rewritten = data.dup
      rewritten[to] = rewritten.delete(from)
      entry.update_columns(data: rewritten.to_json)
    end
  end

  def track_old_associations
    if associations_changed?
      old_value = associations_was
      @old_associations_before_update = begin
        old_value.is_a?(String) ? JSON.parse(old_value) : (old_value || [])
      rescue JSON::ParserError
        []
      end
    else
      @old_associations_before_update = associations_list.deep_dup
    end
  end
end
