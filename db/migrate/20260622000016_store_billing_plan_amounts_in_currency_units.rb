# frozen_string_literal: true

# Billing plan prices are stored in whole currency units (dollars / yuan) rather
# than integer cents. The Payments boundary (which works in minor units) converts
# via Billing::Plan#price_cents_for.
class StoreBillingPlanAmountsInCurrencyUnits < ActiveRecord::Migration[8.1]
  def up
    add_column :billing_plans, :amount_usd, :decimal, precision: 12, scale: 2, default: "0.0", null: false
    add_column :billing_plans, :amount_cny, :decimal, precision: 12, scale: 2, default: "0.0", null: false

    execute <<~SQL.squish
      UPDATE billing_plans
      SET amount_usd = amount_usd_cents / 100.0,
          amount_cny = amount_cny_cents / 100.0
    SQL

    remove_column :billing_plans, :amount_usd_cents
    remove_column :billing_plans, :amount_cny_cents
  end

  def down
    add_column :billing_plans, :amount_usd_cents, :integer, default: 0, null: false
    add_column :billing_plans, :amount_cny_cents, :integer, default: 0, null: false

    execute <<~SQL.squish
      UPDATE billing_plans
      SET amount_usd_cents = CAST(ROUND(amount_usd * 100) AS INTEGER),
          amount_cny_cents = CAST(ROUND(amount_cny * 100) AS INTEGER)
    SQL

    remove_column :billing_plans, :amount_usd
    remove_column :billing_plans, :amount_cny
  end
end
