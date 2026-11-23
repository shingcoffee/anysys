# frozen_string_literal: true

class CreateFeatureModules < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_modules do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :version
      t.text :step_actions
      t.text :configuration_schema
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    add_index :feature_modules, :key, unique: true
    add_index :feature_modules, :status
  end
end
