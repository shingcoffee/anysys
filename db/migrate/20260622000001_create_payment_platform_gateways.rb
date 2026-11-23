# frozen_string_literal: true

class CreatePaymentPlatformGateways < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_platform_gateways do |t|
      t.string  :provider,  null: false
      t.boolean :available, null: false, default: false
      t.timestamps
    end
    add_index :payment_platform_gateways, :provider, unique: true
  end
end
