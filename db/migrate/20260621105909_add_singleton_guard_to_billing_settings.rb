# frozen_string_literal: true

class AddSingletonGuardToBillingSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_settings, :singleton_guard, :integer, null: false, default: 0
    add_index  :billing_settings, :singleton_guard, unique: true,
               name: "index_billing_settings_singleton"
  end
end
