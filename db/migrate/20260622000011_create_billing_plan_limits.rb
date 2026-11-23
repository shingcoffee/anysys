# frozen_string_literal: true

class CreateBillingPlanLimits < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_plan_limits do |t|
      t.references :billing_plan, null: false, foreign_key: true, index: true
      t.string :item_key, null: false
      t.integer :limit_value, null: false, default: -1

      t.timestamps
    end

    add_index :billing_plan_limits, [:billing_plan_id, :item_key], unique: true
  end
end
