# frozen_string_literal: true

class RemoveIsDefaultFromEntityVersions < ActiveRecord::Migration[8.1]
  def up
    remove_index :entity_versions, :is_default if index_exists?(:entity_versions, :is_default)
    remove_index :entity_versions, %i[entity_id is_default],
                 name: "index_entity_versions_on_entity_id_and_is_default" if index_exists?(:entity_versions, %i[entity_id is_default])
    remove_column :entity_versions, :is_default
  end

  def down
    add_column :entity_versions, :is_default, :boolean, default: false, null: false
    add_index :entity_versions, :is_default
    add_index :entity_versions, %i[entity_id is_default],
              name: "index_entity_versions_on_entity_id_and_is_default"
  end
end
