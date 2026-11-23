# frozen_string_literal: true

class RenameJunctionToBridge < ActiveRecord::Migration[8.1]
  def up
    # Rename the database column
    rename_column :entities, :is_junction_entity, :is_bridge_entity

    # Update JSON keys in associations data
    Entity.unscoped.where.not(associations: [nil, "", "[]"]).find_each do |entity|
      associations = begin
        JSON.parse(entity.associations)
      rescue JSON::ParserError
        next
      end

      updated = associations.map do |assoc|
        assoc["bridge_entity_id"] = assoc.delete("junction_entity_id") if assoc.key?("junction_entity_id")
        assoc["bridge_entity_name"] = assoc.delete("junction_entity_name") if assoc.key?("junction_entity_name")
        assoc
      end

      entity.update_column(:associations, updated.to_json)
    end

    # Update bridge entity descriptions
    Entity.unscoped.where(is_bridge_entity: true).find_each do |entity|
      if entity.description&.include?("Junction entity linking")
        entity.update_column(:description, entity.description.gsub("Junction entity linking", "Bridge entity linking"))
      end
    end
  end

  def down
    rename_column :entities, :is_bridge_entity, :is_junction_entity

    Entity.unscoped.where.not(associations: [nil, "", "[]"]).find_each do |entity|
      associations = begin
        JSON.parse(entity.associations)
      rescue JSON::ParserError
        next
      end

      updated = associations.map do |assoc|
        assoc["junction_entity_id"] = assoc.delete("bridge_entity_id") if assoc.key?("bridge_entity_id")
        assoc["junction_entity_name"] = assoc.delete("bridge_entity_name") if assoc.key?("bridge_entity_name")
        assoc
      end

      entity.update_column(:associations, updated.to_json)
    end

    Entity.unscoped.where(is_junction_entity: true).find_each do |entity|
      if entity.description&.include?("Bridge entity linking")
        entity.update_column(:description, entity.description.gsub("Bridge entity linking", "Junction entity linking"))
      end
    end
  end
end
