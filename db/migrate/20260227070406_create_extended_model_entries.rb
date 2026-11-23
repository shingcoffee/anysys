class CreateExtendedModelEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :extended_model_entries do |t|
      # Polymorphic association to any base model (User, Product, Order, etc.)
      t.references :extendable, polymorphic: true, null: false

      # Link to Entity (schema definition)
      t.references :entity, null: false, foreign_key: true

      # Link to EntityEntry (actual data)
      t.references :entity_entry, null: false, foreign_key: true

      # Denormalized for query performance
      t.references :customer, null: false, foreign_key: true

      t.timestamps
    end

    # Composite unique index: one extension of each type per record
    add_index :extended_model_entries,
      [:extendable_type, :extendable_id, :entity_id],
      name: 'idx_extended_model_entries_lookup',
      unique: true

    # Customer + entity index for listing all records of an extension type
    add_index :extended_model_entries,
      [:customer_id, :entity_id],
      name: 'idx_extended_model_entries_customer_entity'

    # Extendable lookup index
    add_index :extended_model_entries,
      [:extendable_type, :extendable_id],
      name: 'idx_extended_model_entries_extendable'
  end
end
