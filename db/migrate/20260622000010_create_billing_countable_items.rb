# frozen_string_literal: true

class CreateBillingCountableItems < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_countable_items do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.boolean :enabled, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :billing_countable_items, :key, unique: true
  end
end
