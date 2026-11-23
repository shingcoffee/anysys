class AddIsJunctionEntityToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :is_junction_entity, :boolean, default: false, null: false
    add_index :entities, :is_junction_entity
    add_index :entities, [:customer_id, :is_junction_entity]
  end
end
