# frozen_string_literal: true

class CreatePageVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :page_versions do |t|
      t.references :page, null: false, foreign_key: true
      t.integer :customer_id
      t.text :configuration, null: false
      t.integer :version_number, null: false
      t.string :description
      t.timestamps
    end

    add_index :page_versions, [:page_id, :version_number], unique: true
    add_index :page_versions, :customer_id
  end
end
