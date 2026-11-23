# frozen_string_literal: true

class CreateBillingInvoiceLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_invoice_line_items do |t|
      t.bigint  :customer_id,           null: false
      t.bigint  :billing_invoice_id,    null: false
      t.string  :description,           null: false
      t.integer :quantity,              null: false, default: 1
      t.integer :unit_amount_cents,     null: false
      t.integer :amount_cents,          null: false
      t.string  :kind,                  null: false
      t.timestamps
    end

    add_index :billing_invoice_line_items, :customer_id
    add_index :billing_invoice_line_items, :billing_invoice_id
  end
end
