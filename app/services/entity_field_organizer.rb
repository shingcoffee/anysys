# frozen_string_literal: true

# Organizes entity fields into categorized sections for the page builder.
# Calculated and computed attributes are left out: forms never submit them.
#
# Separates an entity's fields into own fields and associated entity fields.
#
# @example
#   sections = EntityFieldOrganizer.call(entity)
#   sections[:own_fields]          # => [{name: "title", ...}]
#   sections[:associated_entities] # => [{entity_name: "Course", fields: [...]}]
#
class EntityFieldOrganizer
  EMPTY_SECTIONS = {
    base_fields: {},
    own_fields: [],
    associated_entities: []
  }.freeze

  DERIVED_TYPES = %w[Calculated Computed].freeze

  def self.call(entity)
    new(entity).call
  end

  def self.grouped(entity)
    new(entity).grouped_organized_fields
  end

  def self.primary(entity)
    new(entity).primary
  end

  def initialize(entity)
    @entity = entity
  end

  def call
    return EMPTY_SECTIONS unless @entity

    primary.merge(associated_entities: extract_associated_entities_grouped)
  end

  # The entity's own sections, without looking up its associations.
  def primary
    return EMPTY_SECTIONS.except(:associated_entities) unless @entity

    { base_fields: extract_base_fields, own_fields: extract_own_fields }
  end

  def grouped_organized_fields
    return [] unless @entity
    @entity.grouped_property_schema.map do |section|
      { group: section[:group], fields: section[:attributes].reject { |field| derived?(field) } }
    end
  end

  private

  def derived?(field)
    field.is_a?(Hash) && DERIVED_TYPES.include?(field["type"])
  end

  # A person's account columns reach a form only as identity fields.
  def extract_base_fields
    class_name = @entity.extended_model
    return {} if class_name.blank? || @entity.person?

    klass = class_name.safe_constantize
    return {} unless klass && klass < ApplicationRecord

    system_cols = %w[id customer_id created_at updated_at]
    fields = klass.columns.reject { |c| system_cols.include?(c.name) }.map do |c|
      { "key" => c.name, "name_slug" => c.name, "type" => c.type.to_s }
    end
    { class_name => fields }
  end

  def extract_own_fields
    Array(@entity.property_schema_json).reject { |field| derived?(field) }
  end

  def extract_associated_entities_grouped
    associations = @entity.associations_json || []

    associations.filter_map do |assoc|
      build_merged_association(assoc)
    end
  end

  def resolve_entity(id)
    return nil if id.blank?

    Entity.find_by(id: id)
  end

  def build_merged_association(assoc)
    target_entity = resolve_entity(assoc["target_entity_id"]) if assoc["target_entity_id"].present?
    bridge_entity = resolve_entity(assoc["bridge_entity_id"]) if assoc["bridge_entity_id"].present?

    bridge_fields = extract_bridge_fields(bridge_entity, target_entity&.id)

    return nil unless bridge_entity

    {
      entity_id: target_entity&.id,
      entity_name: target_entity&.name || assoc["target_entity_name"],
      entity_display_label: target_entity&.display_label || assoc["target_entity_name"],
      association_type: assoc["association_type"],
      base_fields: [],
      fields: [],
      bridge_entity_id: bridge_entity&.id,
      bridge_entity_name: bridge_entity&.name,
      bridge_entity_display_label: bridge_entity&.display_label,
      bridge_fields: bridge_fields
    }
  end

  # Extracts bridge entity fields for the sidebar:
  # - The EntityReference to the associated entity (the dropdown linking to its entries)
  # - All additional attributes explicitly defined on the bridge entity
  # The EntityReference to the primary entity is excluded (it is populated automatically).
  def extract_bridge_fields(bridge_entity, target_entity_id)
    return [] unless bridge_entity

    Array(bridge_entity.property_schema_json).reject do |f|
      derived?(f) || (f["type"] == Entity::ENTITY_REFERENCE_TYPE && f["entity_id"].to_s != target_entity_id.to_s)
    end
  end
end
