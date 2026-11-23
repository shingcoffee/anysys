# frozen_string_literal: true

class CreateBillingInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_invoices do |t|
      t.bigint   :customer_id,              null: false
      t.bigint   :billing_subscription_id,  null: false
      t.string   :number
      t.string   :status,                   null: false, default: "draft"
      t.datetime :period_start
      t.datetime :period_end
      t.integer  :subtotal_cents,           null: false, default: 0
      t.integer  :discount_cents,           null: false, default: 0
      t.integer  :tax_cents,                null: false, default: 0
      t.integer  :total_cents,              null: false, default: 0
      t.string   :currency
      t.datetime :due_at
      t.datetime :issued_at
      t.datetime :paid_at
      t.integer  :attempt_count,            null: false, default: 0
      t.datetime :next_attempt_at
      t.bigint   :billing_coupon_id
      t.bigint   :payment_id
      t.string   :collection_mode
      t.timestamps
    end

    add_index :billing_invoices, :customer_id
    add_index :billing_invoices, :billing_subscription_id
    add_index :billing_invoices, :number, unique: true
    add_index :billing_invoices, %i[status next_attempt_at]
  end
end
