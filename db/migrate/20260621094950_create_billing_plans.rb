# frozen_string_literal: true

class CreateBillingPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_plans do |t|
      t.string  :code,         null: false
      t.string  :name,         null: false
      t.text    :description
      t.integer :amount_cents, null: false, default: 0
      t.string  :currency,     null: false, default: "CNY"
      t.string  :interval,     null: false
      t.integer :trial_days,   null: false, default: 0
      t.json    :features
      t.boolean :active,       null: false, default: true
      t.boolean :is_default,   null: false, default: false
      t.integer :position,     null: false, default: 0
      t.timestamps
    end

    add_index :billing_plans, :code, unique: true
    add_index :billing_plans, :active
    add_index :billing_plans, :position
  end
end
