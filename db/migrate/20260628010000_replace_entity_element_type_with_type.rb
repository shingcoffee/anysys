# frozen_string_literal: true

class ReplaceEntityElementTypeWithType < ActiveRecord::Migration[8.1]
  def up
    add_column :entities, :type, :integer, null: false, default: 0
    add_index  :entities, :type

    # Every existing entity is a customer-specific "custom" entity → 0.
    execute "UPDATE entities SET type = 0"

    remove_index  :entities, :element_type
    remove_column :entities, :element_type

    # Shared entities carry NULL customer_id; their versions inherit that.
    change_column_null :entities, :customer_id, true
    change_column_null :entity_versions, :customer_id, true
  end

  def down
    change_column_null :entity_versions, :customer_id, false
    change_column_null :entities, :customer_id, false
    add_column :entities, :element_type, :string, null: false, default: "custom"
    add_index  :entities, :element_type
    execute "UPDATE entities SET element_type = 'custom'"
    remove_index  :entities, :type
    remove_column :entities, :type
  end
end
