# frozen_string_literal: true

# Event-level webhook idempotency ledger. Each inbound PSP notification carries a
# stable event id (Stripe evt_…, PayPal WH-…, WeChat notification id, Alipay
# notify_id). Recording it under a unique (provider, psp_event_id) index lets the
# dispatcher drop duplicate deliveries at the DB layer — protecting event types
# the per-payment terminal-state check does not (refund callbacks, setup-intent
# backfill replays, amount-mutating replays). Every row is inserted "received" by
# WebhookDispatcher and processed async by ProcessWebhookEventJob, which flips it
# to "processed" on success or dead-letters it to "failed" after exhausting
# retries (see ChangePaymentWebhookEventsStatusDefault for the default fix-up).
class CreatePaymentWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_webhook_events do |t|
      t.string   :provider,      null: false
      t.string   :psp_event_id,  null: false
      t.string   :event_type
      t.string   :status,        null: false, default: "processed"
      t.integer  :customer_id
      t.json     :payload,       null: false, default: {}
      t.datetime :processed_at
      t.timestamps
    end

    add_index :payment_webhook_events, %i[provider psp_event_id], unique: true,
              name: "idx_payment_webhook_events_on_provider_and_event"
    add_index :payment_webhook_events, :customer_id
  end
end
