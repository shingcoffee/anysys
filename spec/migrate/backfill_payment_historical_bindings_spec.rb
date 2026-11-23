# frozen_string_literal: true

require "rails_helper"
require_relative "support/legacy_migration_database"
require Rails.root.join("db/migrate/20261011190000_backfill_payment_historical_bindings")

# Migration-boundary coverage moved from the factory-based service spec. The
# service spec retains its provider/evidence matrix; these rows predate _attempt
# and _anysys_verification and use the exact schema at 91b89d3e.
RSpec.describe BackfillPaymentHistoricalBindings do
  include LegacyMigrationDatabase
  self.use_transactional_tests = false

  around { |example| with_legacy_migration_database { example.run } }

  before do
    legacy_insert(:customers, id: 4001, name: "Original purchaser")
    legacy_insert(:customers, id: 4002, name: "Other purchaser")
    legacy_insert(:users, id: 80, customer_id: 4001, email: "legacy@example.test", first_name: "Old", last_name: "Purchaser")
    legacy_insert(:payment_merchant_accounts, id: 10, customer_id: 4001, provider: "stripe", merchant_id: "original-merchant", mode: "production", status: "disabled")
    legacy_insert(:payment_orders, id: 20, customer_id: 4001, external_ref: "old-order", subject: "Old purchase", amount: "19.37", currency: "USD", status: "paid")
    legacy_insert(:payments, id: 30, customer_id: 4001, user_id: 80, payment_order_id: 20, provider: "stripe", flow: "card",
                  amount: "19.37", out_trade_no: "old-trade", psp_transaction_id: "pi_original", status: "succeeded",
                  paid_at: "2026-01-31 13:00:00", prepay_payload: { "client_secret" => "original-secret" }, raw_notify: {})
    legacy_insert(:payment_refunds, id: 40, customer_id: 4001, payment_id: 30, amount: "3.11", out_refund_no: "old-refund",
                  psp_refund_id: "re_original", status: "succeeded", succeeded_at: "2026-02-01 12:00:00")
  end

  def old_verified_event(merchant: "original-merchant", **attributes)
    payload = { "id" => "evt_original", "type" => "payment_intent.succeeded",
                "data" => { "object" => { "object" => "payment_intent", "id" => "pi_original", "metadata" => { "out_trade_no" => "old-trade" } } } }
    legacy_insert(:payment_webhook_events, **{ id: 50, provider: "stripe", psp_event_id: "evt_original", signing_merchant_id: merchant,
                  customer_id: 4001, event_type: "payment_intent.succeeded", payload: payload, status: "received" }.merge(attributes))
  end

  def reject_binding_migration!
    before_schema = legacy_schema_state
    before_rows = LegacyMigrationDatabase::TABLES.to_h { |table| [table, legacy_rows(table)] }
    expect { migrate_legacy_in_child!(described_class) }.to raise_error(ActiveRecord::MigrationError, /merchant evidence is unresolved.*preflight/)
    expect(legacy_schema_state).to eq(before_schema)
    before_rows.each { |table, rows| expect(legacy_rows(table)).to eq(rows), "rejected binding migration changed #{table}" }
  end

  it "maps true old payment/event rows from recorded signer and operation evidence, preserving all financial data and schema" do
    old_verified_event
    before_schema = legacy_schema_state
    before_rows = LegacyMigrationDatabase::TABLES.to_h { |table| [table, legacy_rows(table)] }
    expect(JSON.parse(before_rows.fetch("payments").first.fetch("prepay_payload"))).not_to have_key("_attempt")
    expect(JSON.parse(before_rows.fetch("payment_webhook_events").first.fetch("payload"))).not_to have_key("_anysys_verification")

    migrate_legacy_in_child!(described_class)

    expect(legacy_schema_state).to eq(before_schema)
    before_rows.except("payments", "payment_webhook_events").each { |table, rows| expect(legacy_rows(table)).to eq(rows) }
    payment = legacy_rows(:payments).first
    event = legacy_rows(:payment_webhook_events).first
    expect(payment.except("prepay_payload")).to eq(before_rows.fetch("payments").first.except("prepay_payload"))
    expect(event.except("payload")).to eq(before_rows.fetch("payment_webhook_events").first.except("payload"))
    expect(JSON.parse(payment.fetch("prepay_payload"))).to include("client_secret" => "original-secret",
      "_attempt" => hash_including("provider" => "stripe", "merchant_account_id" => 10, "mode" => "production", "review_reason" => "historical_identity_backfill"))
    expect(JSON.parse(event.fetch("payload"))).to eq(JSON.parse(before_rows.fetch("payment_webhook_events").first.fetch("payload")).merge("_anysys_verification" => { "merchant_account_id" => 10 }))

    rows = [legacy_rows(:payments), legacy_rows(:payment_webhook_events)]
    migrate_legacy_in_child!(described_class)
    expect([legacy_rows(:payments), legacy_rows(:payment_webhook_events)]).to eq(rows)
  end

  it "refuses missing evidence even when exactly one retained tenant/provider account exists" do
    reject_binding_migration!
  end

  it "rejects ambiguous merchant evidence before partially binding an otherwise deterministic old event" do
    old_verified_event
    legacy_insert(:payment_merchant_accounts, id: 11, customer_id: 4001, provider: "stripe", merchant_id: "other-merchant", mode: "sandbox")
    raw = { "object" => "payment_intent", "id" => "pi_original", "metadata" => { "out_trade_no" => "old-trade", "merchant_id" => "other-merchant" } }
    legacy_connection.execute("UPDATE payments SET raw_notify = #{legacy_connection.quote(JSON.generate(raw))} WHERE id = 30")
    reject_binding_migration!
  end

  it "rejects true old cross-tenant signer evidence instead of assigning the foreign merchant account" do
    legacy_insert(:payment_merchant_accounts, id: 11, customer_id: 4002, provider: "stripe", merchant_id: "foreign-merchant", mode: "production")
    old_verified_event(merchant: "foreign-merchant", customer_id: nil)
    reject_binding_migration!
  end

  it "refuses rollback without stripping recovered identities from old financial rows" do
    old_verified_event
    migrate_legacy_in_child!(described_class)
    rows = [legacy_rows(:payments), legacy_rows(:payment_webhook_events)]
    expect { migrate_legacy_in_child!(described_class, direction: :down) }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect([legacy_rows(:payments), legacy_rows(:payment_webhook_events)]).to eq(rows)
  end
end
