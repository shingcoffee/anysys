# frozen_string_literal: true

class AddOnSuccessToPaymentOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_orders, :on_success, :json, default: {}, null: false
  end
end
