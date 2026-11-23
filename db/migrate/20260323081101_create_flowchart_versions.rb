# frozen_string_literal: true

class CreateFlowchartVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :flowchart_versions do |t|
      t.references :flowchart, null: false, foreign_key: true
      t.integer :customer_id
      t.text :configuration, null: false
      t.integer :version_number, null: false
      t.string :description
      t.timestamps
    end

    add_index :flowchart_versions, [:flowchart_id, :version_number], unique: true
    add_index :flowchart_versions, :customer_id
  end
end
