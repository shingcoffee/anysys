class AddExtendableModelToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :extendable_model, :string
    add_index :entities, :extendable_model
    add_index :entities, [:customer_id, :extendable_model]
  end
end
