class RenameResourcesToEntities < ActiveRecord::Migration[8.1]
  def change
    # Rename the resources table to entities
    rename_table :resources, :entities

    # Rename the resource_id column to entity_id in flowcharts
    rename_column :flowcharts, :resource_id, :entity_id

    # Rename the index on entity_id
    rename_index :flowcharts, :index_flowcharts_on_resource_id, :index_flowcharts_on_entity_id
  end
end
