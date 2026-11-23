# frozen_string_literal: true

# Per-customer override heads for shared Pages / Flowcharts (same pattern as
# entity_customer_heads), plus a payload override table for Constants (which
# are not versioned). Tenant-path edits of a shared resource — including
# customer 81721200 — write the override line; Shared Resources writes the
# global default.
class AddSharedResourceCustomerOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :page_customer_heads do |t|
      t.integer :page_id, null: false
      t.integer :customer_id, null: false
      t.integer :current_version_id, null: false
      t.timestamps
    end
    add_index :page_customer_heads, [:page_id, :customer_id], unique: true
    add_index :page_customer_heads, :current_version_id

    create_table :flowchart_customer_heads do |t|
      t.integer :flowchart_id, null: false
      t.integer :customer_id, null: false
      t.integer :current_version_id, null: false
      t.timestamps
    end
    add_index :flowchart_customer_heads, [:flowchart_id, :customer_id], unique: true
    add_index :flowchart_customer_heads, :current_version_id

    create_table :constant_customer_overrides do |t|
      t.integer :constant_id, null: false
      t.integer :customer_id, null: false
      t.json :options, null: false, default: []
      t.timestamps
    end
    add_index :constant_customer_overrides, [:constant_id, :customer_id], unique: true
    add_index :constant_customer_overrides, :customer_id

    split_version_number_index(
      :page_versions,
      columns: [:page_id, :version_number],
      old_name: "index_page_versions_on_page_id_and_version_number",
      global_name: "index_page_versions_global_line",
      customer_name: "index_page_versions_customer_line",
      parent_id: :page_id
    )

    split_version_number_index(
      :flowchart_versions,
      columns: [:flowchart_id, :version_number],
      old_name: "index_flowchart_versions_on_flowchart_id_and_version_number",
      global_name: "index_flowchart_versions_global_line",
      customer_name: "index_flowchart_versions_customer_line",
      parent_id: :flowchart_id
    )
  end

  private

  def split_version_number_index(table, columns:, old_name:, global_name:, customer_name:, parent_id:)
    remove_index table, name: old_name
    add_index table, columns, unique: true, where: "customer_id IS NULL", name: global_name
    add_index table, [parent_id, :customer_id, :version_number], unique: true,
              where: "customer_id IS NOT NULL", name: customer_name
  end
end
