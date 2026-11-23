# frozen_string_literal: true

# Migration to add customer_id to constants for multi-tenancy
#
# Changes:
#   1. Adds customer_id column (nullable)
#   2. Sets customer_id to NULL for all shared constants
#   3. Adds index on customer_id
#   4. Adds partial unique index on (customer_id, name) for customer_specific constants
#
# Shared constants (constant_type = 'shared') have customer_id = NULL and are accessible by all customers.
# Customer-specific constants (constant_type = 'customer_specific') are tenant-scoped with required customer_id.
#
class AddCustomerToConstants < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Add customer_id column (nullable)
    add_column :constants, :customer_id, :integer

    # Step 2: Set customer_id to NULL for all shared constants
    execute <<~SQL
      UPDATE constants
      SET customer_id = NULL
      WHERE constant_type = 'shared'
    SQL

    # Step 3: Add index on customer_id
    add_index :constants, :customer_id

    # Step 4: Add partial unique index for customer_specific constants
    # This ensures name uniqueness within a customer for customer_specific constants
    add_index :constants, [:customer_id, :name],
              unique: true,
              where: "customer_id IS NOT NULL",
              name: "index_constants_on_customer_id_and_name_for_customer_specific"
  end

  def down
    # Remove indices
    remove_index :constants, name: "index_constants_on_customer_id_and_name_for_customer_specific", if_exists: true
    remove_index :constants, :customer_id, if_exists: true

    # Remove column
    remove_column :constants, :customer_id
  end
end
