# frozen_string_literal: true

class CreateCustomerFeatureModules < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_feature_modules do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :feature_module, null: false, foreign_key: true
      t.text :configuration
      t.integer :status, default: 0, null: false
      t.datetime :enabled_at
      t.timestamps
    end

    add_index :customer_feature_modules, [:customer_id, :feature_module_id],
              unique: true, name: "idx_customer_feature_modules_unique"
    add_index :customer_feature_modules, :status
  end
end
