# frozen_string_literal: true

class AddCurrencyToBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_subscriptions, :currency, :string, null: false, default: "USD"
  end
end
