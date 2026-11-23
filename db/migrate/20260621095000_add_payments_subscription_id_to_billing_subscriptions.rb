# frozen_string_literal: true

class AddPaymentsSubscriptionIdToBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_subscriptions, :payments_subscription_id, :bigint, null: true
    add_index  :billing_subscriptions, :payments_subscription_id
  end
end
