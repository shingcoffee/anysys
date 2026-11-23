# frozen_string_literal: true

# Records card disputes / chargebacks raised by the cardholder's bank. A dispute
# is orthogonal to the payment's own status (the money stays captured until the
# dispute is lost), so it lives in its own table linked to the payment rather
# than as a payment state. Keyed by the PSP's dispute id under a unique index so
# repeated dispute webhooks (created → under_review → won/lost) upsert one row.
class CreatePaymentDisputes < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_disputes do |t|
      t.integer  :customer_id,   null: false
      t.integer  :payment_id,    null: false
      t.string   :provider,      null: false
      t.string   :psp_dispute_id, null: false
      t.string   :reason
      t.string   :status,        null: false, default: "open"
      t.integer  :amount_cents,  null: false, default: 0
      t.json     :raw,           null: false, default: {}
      t.datetime :opened_at
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :payment_disputes, %i[provider psp_dispute_id], unique: true,
              name: "idx_payment_disputes_on_provider_and_dispute"
    add_index :payment_disputes, :payment_id
    add_index :payment_disputes, :customer_id
  end
end
