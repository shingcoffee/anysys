# frozen_string_literal: true

# Additive-only. Creates the three content-addressed tables, adds a nullable
# content_id to each version table, and renames default_version_id ->
# current_version_id on each parent. No data is moved here — the destructive
# backfill (20260704130000) runs after the models read through content.
class AddContentAddressedVersioning < ActiveRecord::Migration[8.1]
  CONTENT_TABLES = {
    entity_definition_contents:       :entity_versions,
    flowchart_configuration_contents: :flowchart_versions,
    page_configuration_contents:      :page_versions
  }.freeze

  def up
    CONTENT_TABLES.each_key do |table|
      create_table table do |t|
        t.integer  :customer_id                       # nullable: NULL for shared resources
        t.string   :content_hash, null: false         # SHA-256 hex of canonical JSON
        t.text     :payload,      null: false
        t.datetime :created_at,   null: false
      end
      add_index table, %i[customer_id content_hash], unique: true,
                name: "index_#{table}_on_customer_and_hash"
      add_index table, :customer_id
    end

    CONTENT_TABLES.each_value do |versions_table|
      add_column versions_table, :content_id, :integer   # nullable until backfill
      add_index  versions_table, :content_id
    end

    rename_column :entities,   :default_version_id, :current_version_id
    rename_column :flowcharts, :default_version_id, :current_version_id
    rename_column :pages,      :default_version_id, :current_version_id
  end

  def down
    rename_column :pages,      :current_version_id, :default_version_id
    rename_column :flowcharts, :current_version_id, :default_version_id
    rename_column :entities,   :current_version_id, :default_version_id
    CONTENT_TABLES.each_value { |vt| remove_column vt, :content_id }
    CONTENT_TABLES.each_key   { |t|  drop_table t }
  end
end
