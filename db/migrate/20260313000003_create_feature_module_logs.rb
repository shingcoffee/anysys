# frozen_string_literal: true

class CreateFeatureModuleLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_module_logs do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :feature_module, null: false, foreign_key: true
      t.references :entity_entry, foreign_key: true
      t.string :action, null: false
      t.text :request_data
      t.text :response_data
      t.integer :status, default: 0, null: false
      t.text :error_message
      t.timestamps
    end

    add_index :feature_module_logs, [:customer_id, :feature_module_id],
              name: "idx_feature_module_logs_customer_module"
    add_index :feature_module_logs, :action
    add_index :feature_module_logs, :status
  end
end
