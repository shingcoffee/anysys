# frozen_string_literal: true

# Migration to make blueprint flowcharts shared across all customers
#
# Changes:
#   1. Makes customer_id nullable for flowcharts table
#   2. Sets customer_id to NULL for all blueprint flowcharts
#   3. Updates the unique index on (customer_id, uuid) to handle NULL values
#
# Blueprint flowcharts (flowchart_type = 1) are shared and accessible by any customer.
# Custom flowcharts (flowchart_type = 0) remain tenant-scoped with required customer_id.
#
class MakeBlueprintFlowchartsShared < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Make customer_id nullable
    change_column_null :flowcharts, :customer_id, true

    # Step 2: Set customer_id to NULL for all blueprint flowcharts
    execute <<~SQL
      UPDATE flowcharts
      SET customer_id = NULL
      WHERE flowchart_type = 1
    SQL

    # Step 3: Remove the old unique index on (customer_id, uuid)
    remove_index :flowcharts, [:customer_id, :uuid], if_exists: true

    # Step 4: Add a partial unique index for custom flowcharts (customer_id IS NOT NULL)
    # This ensures uuid uniqueness within a customer for custom flowcharts
    add_index :flowcharts, [:customer_id, :uuid],
              unique: true,
              where: "customer_id IS NOT NULL",
              name: "index_flowcharts_on_customer_id_and_uuid_for_custom"
  end

  def down
    # Remove the partial index
    remove_index :flowcharts, name: "index_flowcharts_on_customer_id_and_uuid_for_custom", if_exists: true

    # Restore the original index (this may fail if there are blueprint flowcharts)
    add_index :flowcharts, [:customer_id, :uuid], unique: true

    # Make customer_id NOT NULL again (this will fail if there are NULL values)
    change_column_null :flowcharts, :customer_id, false
  end
end
