# frozen_string_literal: true

class MakeCustomerIdRequiredOnTenantScopedTables < ActiveRecord::Migration[8.1]
  DEFAULT_CUSTOMER_ID = 96546124

  def up
    # Populate existing records with default customer_id
    execute "UPDATE flowcharts SET customer_id = #{DEFAULT_CUSTOMER_ID} WHERE customer_id IS NULL"
    execute "UPDATE entities SET customer_id = #{DEFAULT_CUSTOMER_ID} WHERE customer_id IS NULL"
    execute "UPDATE entity_entries SET customer_id = #{DEFAULT_CUSTOMER_ID} WHERE customer_id IS NULL"

    # Add NOT NULL constraint
    change_column_null :flowcharts, :customer_id, false
    change_column_null :entities, :customer_id, false
    change_column_null :entity_entries, :customer_id, false

    # Add foreign key constraints
    add_foreign_key :flowcharts, :customers, unless_exists: true
    add_foreign_key :entities, :customers, unless_exists: true
    add_foreign_key :entity_entries, :customers, unless_exists: true
  end

  def down
    # Remove foreign key constraints
    remove_foreign_key :flowcharts, :customers, if_exists: true
    remove_foreign_key :entities, :customers, if_exists: true
    remove_foreign_key :entity_entries, :customers, if_exists: true

    # Remove NOT NULL constraint
    change_column_null :flowcharts, :customer_id, true
    change_column_null :entities, :customer_id, true
    change_column_null :entity_entries, :customer_id, true
  end
end
