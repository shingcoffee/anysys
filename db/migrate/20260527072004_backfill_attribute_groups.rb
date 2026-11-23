# frozen_string_literal: true

# Idempotent backfill: convert legacy `group` string keys on each attribute into
# first-class `attribute_groups` rows + `group_id` references on the attribute.
class BackfillAttributeGroups < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Load IDs first so the SELECT cursor closes before per-row UPDATEs.
    # SQLite serializes I/O on a single connection; iterating an open
    # `find_each` cursor while issuing UPDATEs can trip its busy timeout.
    Entity.unscoped.pluck(:id).each_slice(200) do |slice|
      Entity.unscoped.where(id: slice).to_a.each do |entity|
        attrs  = read_json_array(entity, :property_schema)
        groups = read_json_array(entity, :attribute_groups)

        # Skip if attributes already use group_id (idempotent).
        next if attrs.any? { |a| a["group_id"].present? } && attrs.none? { |a| a["group"].present? }

        legacy_names = attrs.filter_map { |a| a["group"].to_s.strip.presence }.uniq.sort
        next if legacy_names.empty?

        name_to_group = legacy_names.each_with_index.to_h do |name, i|
          slug = "g_legacy_#{i + 1}"
          [name, {
            "id"          => slug,
            "name"        => name,
            "description" => nil,
            "icon"        => EntityAttributeGroupOptions::DEFAULT_ICON,
            "color"       => EntityAttributeGroupOptions::DEFAULT_COLOR
          }]
        end

        new_attrs = attrs.map do |a|
          new_a = a.except("group")
          if (g = a["group"].to_s.strip.presence)
            new_a["group_id"] = name_to_group[g]["id"]
          end
          new_a
        end

        new_groups = groups + name_to_group.values

        entity.update_columns(
          property_schema:  serialize_for_column(Entity, :property_schema, new_attrs),
          attribute_groups: serialize_for_column(Entity, :attribute_groups, new_groups)
        )
      end
    end
  end

  def down
    Entity.unscoped.pluck(:id).each_slice(200) do |slice|
      Entity.unscoped.where(id: slice).to_a.each do |entity|
        attrs = read_json_array(entity, :property_schema)
        next if attrs.none? { |a| a["group_id"].present? }
        new_attrs = attrs.map { |a| a.except("group_id") }
        entity.update_columns(
          property_schema:  serialize_for_column(Entity, :property_schema, new_attrs),
          attribute_groups: serialize_for_column(Entity, :attribute_groups, [])
        )
      end
    end
  end

  private

  # Read a JSON-or-Array column robustly. SQLite + `t.text` returns a String;
  # PG + `jsonb` returns the parsed Array. We normalize to an Array.
  def read_json_array(record, attr)
    raw = record.read_attribute(attr)
    case raw
    when String then (JSON.parse(raw) rescue [])
    when nil    then []
    else raw
    end
  end

  # Serialize a value for write so it matches the column's storage shape:
  # text columns get a JSON string; native json/jsonb columns get the Ruby value.
  def serialize_for_column(model, attr, value)
    col = model.columns_hash[attr.to_s]
    case col&.sql_type_metadata&.type
    when :json, :jsonb then value
    else value.to_json
    end
  end
end
