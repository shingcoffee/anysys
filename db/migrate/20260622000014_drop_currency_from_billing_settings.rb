# frozen_string_literal: true

class DropCurrencyFromBillingSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :billing_settings, :currency, :string
  end
end
