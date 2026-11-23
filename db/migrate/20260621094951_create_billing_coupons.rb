# frozen_string_literal: true

class CreateBillingCoupons < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_coupons do |t|
      t.string   :code,                null: false
      t.string   :name,                null: false
      t.string   :discount_type,       null: false
      t.integer  :percent_off
      t.integer  :amount_off_cents
      t.string   :currency
      t.string   :duration,            null: false
      t.integer  :duration_in_cycles
      t.integer  :max_redemptions
      t.integer  :times_redeemed,      null: false, default: 0
      t.datetime :redeem_by
      t.boolean  :active,              null: false, default: true
      t.timestamps
    end

    add_index :billing_coupons, :code, unique: true
    add_index :billing_coupons, :active
  end
end
