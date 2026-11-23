# frozen_string_literal: true

class DualCurrencyBillingPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_plans, :amount_usd_cents, :integer, null: false, default: 0
    add_column :billing_plans, :amount_cny_cents, :integer, null: false, default: 0
    remove_column :billing_plans, :amount_cents, :integer
    remove_column :billing_plans, :currency, :string
    remove_column :billing_plans, :features, :json
  end
end
