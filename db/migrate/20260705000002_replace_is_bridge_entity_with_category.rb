# frozen_string_literal: true

# Replaces the two-valued `is_bridge_entity` boolean with a 3-valued `category`
# enum on entities:
#   plain     — a normal entity
#   bridge    — a junction entity materializing an entity↔entity association
#   extension — an entity that extends a base AR model
class ReplaceIsBridgeEntityWithCategory < ActiveRecord::Migration[8.1]
  def up
    add_column :entities, :category, :integer, default: 0, null: false

    # Backfill: existing bridge entities → :bridge (1); everything else stays :plain (0).
    execute "UPDATE entities SET category = 1 WHERE is_bridge_entity = #{quoted_true}"

    add_index :entities, [:customer_id, :category]
    add_index :entities, :category

    remove_index :entities, column: [:customer_id, :is_bridge_entity],
                            name: "index_entities_on_customer_id_and_is_bridge_entity"
    remove_index :entities, column: :is_bridge_entity,
                            name: "index_entities_on_is_bridge_entity"
    remove_column :entities, :is_bridge_entity
  end

  def down
    add_column :entities, :is_bridge_entity, :boolean, default: false, null: false
    execute "UPDATE entities SET is_bridge_entity = #{quoted_true} WHERE category = 1"

    add_index :entities, [:customer_id, :is_bridge_entity],
              name: "index_entities_on_customer_id_and_is_bridge_entity"
    add_index :entities, :is_bridge_entity,
              name: "index_entities_on_is_bridge_entity"

    remove_index :entities, column: [:customer_id, :category]
    remove_index :entities, column: :category
    remove_column :entities, :category
  end
end
