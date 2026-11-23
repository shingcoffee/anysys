# frozen_string_literal: true

# Per-customer head pointer for shared entities. A shared entity has one global
# default head (entities.current_version_id) plus, for each customer that has
# overridden it, one row here pointing at that customer's current override
# version. Reads resolve the customer's head when present, else the global
# default (see Versionable#resolved_current_version).
class CreateEntityCustomerHeads < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_customer_heads do |t|
      t.integer :entity_id, null: false
      t.integer :customer_id, null: false
      t.integer :current_version_id, null: false
      t.timestamps
    end

    add_index :entity_customer_heads, [:entity_id, :customer_id], unique: true
    add_index :entity_customer_heads, :current_version_id

    # entity_versions numbering is now per-line (global default line = customer_id
    # NULL; each customer override line = that customer_id). Replace the single
    # unique index with two NULL-safe partial indexes so numbering is independent.
    remove_index :entity_versions, column: [:entity_id, :version_number],
                                   name: "index_entity_versions_on_entity_id_and_version_number"
    add_index :entity_versions, [:entity_id, :version_number], unique: true,
              where: "customer_id IS NULL",
              name: "index_entity_versions_global_line"
    add_index :entity_versions, [:entity_id, :customer_id, :version_number], unique: true,
              where: "customer_id IS NOT NULL",
              name: "index_entity_versions_customer_line"
  end
end
