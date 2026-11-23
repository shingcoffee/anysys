# frozen_string_literal: true

class CreateBillingSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_settings do |t|
      t.string  :currency,                   null: false, default: "CNY"
      t.integer :tax_rate_bps,               null: false, default: 0
      t.string  :collection_mode,            null: false, default: "manual"
      t.string  :gateway_provider
      t.json    :dunning_schedule
      t.integer :grace_period_days,          null: false, default: 7
      t.integer :trial_ending_notice_days,   null: false, default: 3
      t.timestamps
    end
  end
end
