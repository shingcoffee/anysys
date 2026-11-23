# frozen_string_literal: true

class CreateBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_subscriptions do |t|
      t.bigint   :customer_id,          null: false
      t.bigint   :billing_plan_id,      null: false
      t.string   :status,               null: false
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :trial_end
      t.boolean  :cancel_at_period_end, null: false, default: false
      t.integer  :amount_cents,         null: false
      t.string   :interval,             null: false
      t.bigint   :billing_coupon_id
      t.datetime :started_at
      t.datetime :cancelled_at
      t.datetime :ended_at
      t.timestamps
    end

    add_index :billing_subscriptions, :customer_id
    add_index :billing_subscriptions, :billing_plan_id
    add_index :billing_subscriptions, :billing_coupon_id
    add_index :billing_subscriptions, :status

    # Partial unique index: at most one live subscription per tenant
    add_index :billing_subscriptions,
              :customer_id,
              unique: true,
              where: "status IN ('trialing','active','past_due','paused')",
              name: "index_billing_subscriptions_on_customer_id_live_unique"
  end
end
