# frozen_string_literal: true

require "rails_helper"
require_relative "support/legacy_migration_database"
require Rails.root.join("db/migrate/20261011000100_add_billing_subscription_lifecycle")

RSpec.describe AddBillingSubscriptionLifecycle do
  include LegacyMigrationDatabase
  self.use_transactional_tests = false

  around { |example| with_legacy_migration_database { example.run } }

  before do
    legacy_insert(:customers, id: 81721200, name: "Platform")
    legacy_insert(:customers, id: 4001, name: "Purchaser")
    legacy_insert(:customers, id: 4002, name: "Other purchaser")
    legacy_insert(:billing_settings, tax_rate_bps: 750, grace_period_days: 3, collection_mode: "manual", dunning_schedule: [1, 4, 9])
    legacy_insert(:billing_plans, id: 10, code: "old-offering", name: "Original offering", interval: "monthly", amount_usd: "99.99", amount_cny: "699.99")
    { page: 17, entity: 8, member: 2 }.each do |key, limit|
      legacy_insert(:billing_plan_limits, billing_plan_id: 10, item_key: key.to_s, limit_value: limit)
    end
    legacy_insert(:billing_subscriptions, id: 20, customer_id: 4001, billing_plan_id: 10, amount_cents: 1234,
                  currency: "USD", interval: "monthly", status: "active", started_at: "2026-01-31 12:00:00",
                  current_period_start: "2026-01-31 12:00:00", current_period_end: "2026-02-28 12:00:00")
    invoice(id: 30, status: "paid", number: "INV-4001-00007", paid_at: "2026-01-31 13:00:00")
    legacy_insert(:billing_invoice_line_items, id: 40, customer_id: 4001, billing_invoice_id: 30, kind: "subscription",
                  description: "Accepted historical price", quantity: 1, unit_amount_cents: 1234, amount_cents: 1234)
  end

  def invoice(id:, **attributes)
    legacy_insert(:billing_invoices, **{ id: id, customer_id: 4001, billing_subscription_id: 20, currency: "USD",
                  period_start: "2026-01-31 12:00:00", period_end: "2026-02-28 12:00:00", due_at: "2026-01-31 12:00:00",
                  collection_mode: "manual", subtotal_cents: 1234, discount_cents: 111, tax_cents: 84, total_cents: 1207 }.merge(attributes))
  end

  def mandate(id:, **attributes)
    legacy_insert(:payment_subscriptions, **{ id: id, customer_id: 81721200, external_ref: "billing-pm-#{id}",
                  provider: "alipay", plan_name: "Historical mandate", cycle: "monthly", currency: "USD", amount: "12.34",
                  status: "active", psp_agreement_id: "agreement-#{id}", next_charge_at: "2026-02-28 12:00:00",
                  charge_claimed_at: "2026-02-28 11:59:00" }.merge(attributes))
  end

  def billing_method(id: 60, **attributes)
    legacy_insert(:billing_payment_methods, **{ id: id, customer_id: 4001, provider: "alipay", status: "active",
                  is_default: true, authorized_at: "2026-01-31 11:00:00", payments_subscription_id: 50 }.merge(attributes))
  end

  def reject_preflight!(key, evidence)
    before_schema = legacy_schema_state
    before_rows = LegacyMigrationDatabase::TABLES.to_h { |table| [table, legacy_rows(table)] }
    findings = described_class.report(legacy_connection)
    writes = []
    capture = ->(*args) do
      sql = args.last.fetch(:sql)
      writes << sql if sql.match?(/\A\s*(ALTER|CREATE|DROP|INSERT|UPDATE|DELETE|REPLACE)\b/i)
    end
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
      expect { migrate_legacy!(described_class) }.to raise_error(ActiveRecord::MigrationError, /Billing preflight conflicts/)
    end
    expect(findings).to include(key => evidence)
    expect(writes).to eq([]), "preflight attempted DDL/data writes: #{writes.inspect}"
    expect(legacy_schema_state).to eq(before_schema)
    before_rows.each { |table, rows| expect(legacy_rows(table)).to eq(rows), "preflight changed #{table}" }
  end

  it "migrates the actual old schema without touching the application connection or provider boundary" do
    expect(legacy_connection).not_to equal(ActiveRecord::Base.connection)
    expect(legacy_connection.column_exists?(:billing_subscriptions, :plan_snapshot)).to be(false)
    expect(legacy_connection.table_exists?(:billing_plan_changes)).to be(false)
    expect(described_class.report(legacy_connection)).to eq({})
    expect(Payments::Gateway).not_to receive(:charge)
    expect(Payments::Gateway).not_to receive(:subscribe)
    expect(Payments::Gateway).not_to receive(:query)

    migrate_legacy!(described_class)

    expect(legacy_connection.table_exists?(:billing_plan_changes)).to be(true)
    expect(legacy_connection.select_all("PRAGMA foreign_key_check").to_a).to eq([])
  end

  it "preserves every legacy financial, period, status and line field, using purchased price rather than today's catalog" do
    legacy_insert(:billing_invoice_line_items, id: 41, customer_id: 4001, billing_invoice_id: 30, kind: "discount",
                  description: "Accepted discount", quantity: 1, unit_amount_cents: -111, amount_cents: -111)
    legacy_insert(:billing_invoice_line_items, id: 42, customer_id: 4001, billing_invoice_id: 30, kind: "tax",
                  description: "Accepted tax", quantity: 1, unit_amount_cents: 84, amount_cents: 84)
    before_subscription = legacy_rows(:billing_subscriptions).first.except("payments_subscription_id")
    before_invoice = legacy_rows(:billing_invoices).first
    before_lines = legacy_rows(:billing_invoice_line_items)

    migrate_legacy!(described_class)

    subscription = legacy_rows(:billing_subscriptions).first
    expect(subscription.slice(*before_subscription.keys)).to eq(before_subscription)
    expect(legacy_rows(:billing_invoices).first.slice(*before_invoice.keys)).to eq(before_invoice)
    expect(legacy_rows(:billing_invoice_line_items)).to eq(before_lines)
    expect(JSON.parse(subscription.fetch("plan_snapshot"))).to include("amount_cents" => 1234, "currency" => "USD",
      "interval" => "monthly", "limits" => { "page" => 17, "entity" => 8, "member" => 2 }, "reconstructed" => true)
    expect(subscription).to include("billing_anchor_day" => 31, "billing_anchor_month" => 1)
    expect(JSON.parse(legacy_rows(:billing_invoices).first.fetch("terms_snapshot"))).to include("tax_rate_bps" => 750,
      "grace_period_days" => 3, "dunning_schedule" => [1, 4, 9], "collection_mode" => "manual")
  end

  it "preserves CNY yearly purchased terms even when the current catalog has different prices and cadence" do
    legacy_connection.execute("UPDATE billing_subscriptions SET currency = 'CNY', interval = 'yearly', amount_cents = 54321, current_period_end = '2027-01-31 12:00:00'")
    legacy_connection.execute("UPDATE billing_invoices SET currency = 'CNY', subtotal_cents = 54321, discount_cents = 0, tax_cents = 0, total_cents = 54321, period_end = '2027-01-31 12:00:00'")
    legacy_connection.execute("UPDATE billing_invoice_line_items SET unit_amount_cents = 54321, amount_cents = 54321")
    before_invoice = legacy_rows(:billing_invoices).first

    migrate_legacy!(described_class)

    expect(JSON.parse(legacy_rows(:billing_subscriptions).first.fetch("plan_snapshot"))).to include("amount_cents" => 54321,
      "currency" => "CNY", "interval" => "yearly")
    expect(legacy_rows(:billing_invoices).first.slice(*before_invoice.keys)).to eq(before_invoice)
  end

  it "initializes each sequence from its maximum valid suffix despite drafts, deleted interior numbers and gaps" do
    invoice(id: 31, status: "void", number: "INV-4001-00031")
    legacy_connection.execute("DELETE FROM billing_invoices WHERE id = 31")
    invoice(id: 32, status: "open", number: "INV-4001-00042")
    invoice(id: 33, status: "draft", number: nil, due_at: nil)
    invoice(id: 34, status: "draft", number: "INV-4001-00073")
    invoice(id: 35, status: "void", number: "INV-4002-99999")
    legacy_insert(:billing_subscriptions, id: 21, customer_id: 4002, billing_plan_id: 10, amount_cents: 0, currency: "USD",
                  interval: "monthly", status: "cancelled", current_period_start: "2026-01-31 12:00:00", current_period_end: "2026-02-28 12:00:00")
    invoice(id: 36, customer_id: 4002, billing_subscription_id: 21, status: "paid", number: "INV-4002-00105")
    numbers = legacy_rows(:billing_invoices, columns: "id,number")

    migrate_legacy!(described_class)

    expect(legacy_rows(:billing_invoice_sequences).map { |row| row.slice("customer_id", "last_value") }).to contain_exactly(
      { "customer_id" => 4001, "last_value" => 73 }, { "customer_id" => 4002, "last_value" => 105 })
    expect(legacy_rows(:billing_invoices, columns: "id,number")).to eq(numbers)
  end

  it "marks only explicitly linked platform mandates billing-owned and retains ordinary Payments schedules and financial identity" do
    mandate(id: 50)
    mandate(id: 51, customer_id: 4002, external_ref: "member-renewal")
    billing_method
    before_mandates = legacy_rows(:payment_subscriptions)

    migrate_legacy!(described_class)

    billing, ordinary = legacy_rows(:payment_subscriptions)
    expect(billing.slice(*before_mandates.first.keys).except("next_charge_at", "charge_claimed_at")).to eq(
      before_mandates.first.except("next_charge_at", "charge_claimed_at"))
    expect(billing).to include("managed_by" => "billing", "next_charge_at" => nil, "charge_claimed_at" => nil)
    expect(JSON.parse(billing.fetch("metadata"))).to include("billing_owned" => true, "billing_payment_method_id" => 60, "billing_customer_id" => 4001)
    expect(ordinary.slice(*before_mandates.last.keys)).to eq(before_mandates.last)
    expect(ordinary.fetch("managed_by")).to eq("payments")
    expect(legacy_rows(:billing_payment_methods).first).to include("merchant_account_id" => nil, "failure_code" => "historical_authorization_review")
  end

  it "retains references to archived catalog rows and prevents hard deletion of their financial history" do
    legacy_insert(:billing_coupons, id: 70, code: "accepted-coupon", name: "Accepted coupon", discount_type: "percent", percent_off: 10, duration: "forever")
    legacy_connection.execute("UPDATE billing_invoices SET billing_coupon_id = 70 WHERE id = 30")
    migrate_legacy!(described_class)
    legacy_connection.execute("UPDATE billing_plans SET archived_at = '2026-03-01 00:00:00', active = 0 WHERE id = 10")
    legacy_connection.execute("UPDATE billing_coupons SET archived_at = '2026-03-01 00:00:00', active = 0 WHERE id = 70")

    expect { legacy_connection.execute("DELETE FROM billing_plans WHERE id = 10") }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { legacy_connection.execute("DELETE FROM billing_coupons WHERE id = 70") }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(legacy_rows(:billing_invoices).first).to include("billing_subscription_id" => 20, "billing_coupon_id" => 70, "total_cents" => 1207)
  end

  it "marks the earliest accepted trial without shifting the trial or service dates" do
    legacy_connection.execute("UPDATE billing_subscriptions SET status = 'trialing', trial_end = '2026-02-07 12:00:00'")
    legacy_insert(:billing_subscriptions, id: 21, customer_id: 4001, billing_plan_id: 10, amount_cents: 1234, currency: "USD",
                  interval: "monthly", status: "cancelled", started_at: "2025-10-31 12:00:00", trial_end: "2025-11-07 12:00:00",
                  current_period_start: "2025-10-31 12:00:00", current_period_end: "2025-11-30 12:00:00")
    dates = legacy_rows(:billing_subscriptions, columns: "id,trial_end,current_period_start,current_period_end")

    migrate_legacy!(described_class)

    expect(legacy_rows(:customers).find { |row| row["id"] == 4001 }.fetch("trial_used_at")).to eq("2025-10-31 12:00:00")
    expect(legacy_rows(:billing_subscriptions, columns: "id,trial_end,current_period_start,current_period_end")).to eq(dates)
  end

  {
    "orphan:billing_subscriptions.billing_plan_id" => ["UPDATE billing_subscriptions SET billing_plan_id = 999", [20]],
    "orphan:billing_subscriptions.customer_id" => ["UPDATE billing_subscriptions SET customer_id = 999", [20]],
    "orphan:billing_invoices.payment_id" => ["UPDATE billing_invoices SET payment_id = 999", [30]],
    "orphan:billing_invoice_line_items.billing_invoice_id" => ["UPDATE billing_invoice_line_items SET billing_invoice_id = 999", [40]],
    "invoice_tenant_mismatch" => ["UPDATE billing_invoices SET customer_id = 4002", [30]],
    "line_tenant_mismatch" => ["UPDATE billing_invoice_line_items SET customer_id = 4002", [40]],
    "invalid_invoice_amounts" => ["UPDATE billing_invoices SET total_cents = -1", [30]],
    "invalid_catalog_amounts" => ["UPDATE billing_plans SET amount_usd = -1", [10]],
    "unsupported_subscription_currency" => ["UPDATE billing_subscriptions SET currency = 'EUR'", [20]],
    "invalid_periods" => ["UPDATE billing_subscriptions SET current_period_end = current_period_start", [20]]
  }.each do |key, (sql, evidence)|
    it "rejects #{key} by recorded ID before changing schema or history" do
      legacy_connection.execute(sql)
      reject_preflight!(key, evidence)
    end
  end

  it "refuses duplicate legacy invoice numbers rather than renumbering them" do
    legacy_connection.remove_index(:billing_invoices, name: "index_billing_invoices_on_number")
    invoice(id: 31, status: "paid", number: "INV-4001-00007")
    reject_preflight!("duplicate_invoice_numbers", ["INV-4001-00007"])
  end

  it "detects a pending/live duplicate that the old partial unique index did not cover" do
    legacy_insert(:billing_subscriptions, id: 21, customer_id: 4001, billing_plan_id: 10, amount_cents: 1234, currency: "USD",
                  interval: "monthly", status: "pending", current_period_start: "2026-01-31 12:00:00", current_period_end: "2026-02-28 12:00:00")
    reject_preflight!("duplicate_live_customers", [4001])
  end

  it "refuses to assign billing ownership to a foreign-tenant mandate" do
    mandate(id: 50, customer_id: 4002)
    billing_method
    reject_preflight!("invalid_mandate_links", [60])
  end

  it "refuses provider-mismatched billing mandate links" do
    mandate(id: 50, provider: "stripe")
    billing_method
    reject_preflight!("invalid_mandate_links", [60])
  end

  it "refuses a mandate shared by two purchasers" do
    mandate(id: 50)
    billing_method
    billing_method(id: 61, customer_id: 4002)
    reject_preflight!("shared_mandates", [50])
  end

  it "reports a billing-prefixed mandate with no explicit billing owner instead of guessing from its reference" do
    mandate(id: 50)
    reject_preflight!("unmapped_billing_mandates", [50])
  end

  it "refuses unknown historical coupon consumption rather than resetting financial cycles" do
    legacy_insert(:billing_coupons, id: 70, code: "old-repeating", name: "Old discount", discount_type: "percent", percent_off: 10,
                  duration: "repeating", duration_in_cycles: 3, times_redeemed: 1)
    legacy_connection.execute("UPDATE billing_subscriptions SET billing_coupon_id = 70")
    reject_preflight!("unknown_historical_coupon_cycles", [20])
  end

  def historical_collection(status:, **attributes)
    order = { id: 80, customer_id: 81721200, external_ref: "billing-inv-30", subject: "Historical billing collection",
              amount: "12.07", currency: "USD", status: "paid" }
    legacy_insert(:payment_orders, **order.merge(attributes.slice(:customer_id, :amount, :currency)))
    legacy_insert(:payments, **{ id: 90, customer_id: 81721200, payment_order_id: 80, provider: "stripe", flow: "card",
                  amount: "12.07", out_trade_no: "historical-billing-trade", psp_transaction_id: "pi_billing", status: status }.merge(attributes.except(:currency)))
  end

  it "refuses unfinished provider collections with their original payment ID" do
    historical_collection(status: "pending")
    reject_preflight!("unfinished_billing_collections", [90])
  end

  it "refuses unprojected successful captures rather than creating another collection identity" do
    historical_collection(status: "succeeded")
    legacy_connection.execute("UPDATE billing_invoices SET status = 'open', paid_at = NULL WHERE id = 30")
    reject_preflight!("unprojected_captures", [90])
  end

  it "accepts an exact platform capture binding without rewriting the payment, order or invoice financial fields" do
    historical_collection(status: "succeeded")
    legacy_connection.execute("UPDATE billing_invoices SET payment_id = 90 WHERE id = 30")
    payment = legacy_rows(:payments)
    order = legacy_rows(:payment_orders)
    accepted_invoice = legacy_rows(:billing_invoices).first

    migrate_legacy!(described_class)

    expect(legacy_rows(:payments)).to eq(payment)
    expect(legacy_rows(:payment_orders)).to eq(order)
    expect(legacy_rows(:billing_invoices).first.slice(*accepted_invoice.keys)).to eq(accepted_invoice)
  end

  {
    "foreign-tenant payment" => { customer_id: 4002 },
    "wrong captured amount" => { amount: "99.99" },
    "wrong order currency" => { currency: "CNY" }
  }.each do |description, attributes|
    it "refuses an existing but #{description} linked to a paid billing invoice" do
      historical_collection(status: "succeeded", **attributes)
      legacy_connection.execute("UPDATE billing_invoices SET payment_id = 90 WHERE id = 30")
      reject_preflight!("invoice_payment_mismatch", [30])
    end
  end

  %w[open uncollectible].each do |status|
    it "refuses MIG-L1: positive active nontrial enrollment with an unpaid #{status} manual initial invoice" do
      legacy_connection.execute("UPDATE billing_invoices SET status = '#{status}', paid_at = NULL WHERE id = 30")
      reject_preflight!("unpaid_active_initial_intents", [20])
    end

    it "refuses MIG-L2: an unpaid #{status} manual proration with no recorded target intent" do
      invoice(id: 31, status: status, number: "INV-4001-00008")
      legacy_insert(:billing_invoice_line_items, id: 41, customer_id: 4001, billing_invoice_id: 31, kind: "proration",
                    description: "Unpaid legacy upgrade", quantity: 1, unit_amount_cents: 1207, amount_cents: 1207)
      reject_preflight!("unresolved_proration_intents", [31])
    end
  end

  describe "current-period settlement coverage" do
    before { travel_to Time.utc(2026, 10, 12, 12) }

    def advanced_renewal(status: "open", **attributes)
      legacy_connection.execute("UPDATE billing_subscriptions SET started_at = '2026-09-01 12:00:00', current_period_start = '2026-10-01 12:00:00', current_period_end = '2026-11-01 12:00:00' WHERE id = 20")
      legacy_connection.execute("UPDATE billing_invoices SET period_start = '2026-09-01 12:00:00', period_end = '2026-10-01 12:00:00', due_at = '2026-09-01 12:00:00', paid_at = '2026-09-01 13:00:00' WHERE id = 30")
      invoice(id: 31, status: status, number: "INV-4001-00008", period_start: "2026-10-01 12:00:00",
              period_end: "2026-11-01 12:00:00", due_at: "2026-10-01 12:00:00", **attributes)
    end

    def migrate_preserving_window!
      expect(described_class.report(legacy_connection)).to eq({})
      subscription = legacy_rows(:billing_subscriptions).first.except("payments_subscription_id")
      invoices = legacy_rows(:billing_invoices)
      lines = legacy_rows(:billing_invoice_line_items)

      migrate_legacy!(described_class)

      expect(legacy_rows(:billing_subscriptions).first.slice(*subscription.keys)).to eq(subscription)
      expect(legacy_rows(:billing_invoices).map { |row| row.slice(*invoices.first.keys) }).to eq(invoices)
      expect(legacy_rows(:billing_invoice_line_items)).to eq(lines)
      expect(described_class.report(legacy_connection)).to eq({})
    end

    %w[open uncollectible draft].each do |status|
      it "refuses an advanced #{status} manual renewal after grace despite the previous paid base, with no DDL or schedule writes" do
        attributes = status == "draft" ? { subtotal_cents: 0, discount_cents: 0, tax_cents: 0, total_cents: 0 } : {}
        advanced_renewal(status: status, **attributes)
        mandate(id: 50)
        billing_method
        mandate(id: 51, customer_id: 4002, external_ref: "ordinary-recurring")
        expect(legacy_connection.table_exists?(:billing_plan_changes)).to be(false)
        expect(legacy_connection.column_exists?(:billing_invoices, :purpose)).to be(false)
        expect(described_class.report(legacy_connection)).to eq("unpaid_active_current_periods" => [20])
        reject_preflight!("unpaid_active_current_periods", [20])
      end
    end

    it "refuses advanced unpaid access even within grace, rather than treating grace as settlement" do
      travel_to Time.utc(2026, 10, 2, 12)
      advanced_renewal
      reject_preflight!("unpaid_active_current_periods", [20])
    end

    it "refuses the advanced period when its invoice is absent rather than relying on September payment" do
      advanced_renewal
      legacy_connection.execute("DELETE FROM billing_invoices WHERE id = 31")
      reject_preflight!("unpaid_active_current_periods", [20])
    end

    ["2026-09-08 12:00:00", "2026-12-01 12:00:00"].each do |trial_end|
      it "does not exempt an advanced unpaid period merely because trial_end is retained as #{trial_end}" do
        advanced_renewal
        legacy_connection.execute("UPDATE billing_subscriptions SET trial_end = #{legacy_connection.quote(trial_end)} WHERE id = 20")
        reject_preflight!("unpaid_active_current_periods", [20])
      end
    end

    it "refuses an expired original active trial without paid coverage" do
      legacy_connection.execute("UPDATE billing_subscriptions SET started_at = '2026-10-01 12:00:00', current_period_start = '2026-10-01 12:00:00', current_period_end = '2026-10-08 12:00:00', trial_end = '2026-10-08 12:00:00' WHERE id = 20")
      legacy_connection.execute("UPDATE billing_invoices SET status = 'open', paid_at = NULL WHERE id = 30")
      reject_preflight!("unpaid_active_current_periods", [20])
    end

    it "preserves a genuinely ongoing original active trial and its original trial end without requiring payment" do
      legacy_connection.execute("UPDATE billing_subscriptions SET started_at = '2026-10-01 12:00:00', current_period_start = '2026-10-01 12:00:00', current_period_end = '2026-10-20 12:00:00', trial_end = '2026-10-20 12:00:00' WHERE id = 20")
      legacy_connection.execute("UPDATE billing_invoices SET status = 'draft', paid_at = NULL WHERE id = 30")
      migrate_preserving_window!
      expect(legacy_rows(:customers).find { |row| row["id"] == 4001 }.fetch("trial_used_at")).to eq("2026-10-01 12:00:00")
      expect(legacy_rows(:billing_invoices).first.fetch("entitlements_applied_at")).to be_nil
    end

    it "does not waive settlement for an original active trial that has not started" do
      legacy_connection.execute("UPDATE billing_subscriptions SET started_at = '2026-10-20 12:00:00', current_period_start = '2026-10-20 12:00:00', current_period_end = '2026-10-27 12:00:00', trial_end = '2026-10-27 12:00:00' WHERE id = 20")
      legacy_connection.execute("UPDATE billing_invoices SET status = 'open', paid_at = NULL WHERE id = 30")
      reject_preflight!("unpaid_active_current_periods", [20])
    end

    %w[pending trialing past_due paused cancelled expired].each do |status|
      it "preserves historical #{status} state and unpaid debt instead of manufacturing active coverage" do
        advanced_renewal
        legacy_connection.execute("UPDATE billing_subscriptions SET status = '#{status}', trial_end = '2026-09-08 12:00:00', past_due_at = '2026-10-01 12:00:00' WHERE id = 20")
        migrate_preserving_window!
        expect(legacy_rows(:billing_invoices).last.fetch("entitlements_applied_at")).to be_nil
      end
    end

    [1207, 0].each do |total|
      it "preserves a fully settled current manual window with total #{total} and no PSP FK" do
        advanced_renewal(status: "paid", total_cents: total, paid_at: "2026-10-01 13:00:00")
        migrate_preserving_window!
        expect(legacy_rows(:billing_invoices).last).to include("purpose" => "renewal", "payment_id" => nil,
          "entitlements_applied_at" => "2026-10-01 13:00:00")
      end
    end

    it "preserves a legitimate free current window without demanding settlement of old debt" do
      advanced_renewal
      legacy_connection.execute("UPDATE billing_subscriptions SET amount_cents = 0 WHERE id = 20")
      migrate_preserving_window!
    end

    it "preserves a paid renewal after a historical trial without clearing trial history" do
      advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
      legacy_connection.execute("UPDATE billing_subscriptions SET trial_end = '2026-09-08 12:00:00' WHERE id = 20")
      migrate_preserving_window!
    end

    it "preserves a settled proration with a fully paid current base even without a legacy target table" do
      advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
      invoice(id: 32, status: "paid", number: "INV-4001-00009", paid_at: "2026-10-15 13:00:00",
              period_start: "2026-10-15 12:00:00", period_end: "2026-11-01 12:00:00")
      legacy_insert(:billing_invoice_line_items, id: 41, customer_id: 4001, billing_invoice_id: 32, kind: "proration",
                    description: "Settled legacy upgrade", quantity: 1, unit_amount_cents: 1207, amount_cents: 1207)
      migrate_preserving_window!
      expect(legacy_rows(:billing_invoices).last.fetch("purpose")).to eq("proration")
    end

    it "does not let a paid proration alone buy an advanced recurring period" do
      advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
      legacy_insert(:billing_invoice_line_items, id: 41, customer_id: 4001, billing_invoice_id: 31, kind: "proration",
                    description: "Settled adjustment only", quantity: 1, unit_amount_cents: 1207, amount_cents: 1207)
      reject_preflight!("unpaid_active_current_periods", [20])
    end

    it "honors explicit current-schema proration purpose even when imported legacy lines omit its kind" do
      advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
      migrate_preserving_window!
      legacy_connection.execute("UPDATE billing_invoices SET purpose = 'proration' WHERE id = 31")
      expect(described_class.report(legacy_connection)).to eq("unpaid_active_current_periods" => [20])
    end

    it "accepts a partial target period contained wholly in a settled recurring window, without requiring equal endpoints" do
      advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
      legacy_connection.execute("UPDATE billing_subscriptions SET current_period_start = '2026-10-15 12:00:00', current_period_end = '2026-10-25 12:00:00' WHERE id = 20")
      migrate_preserving_window!
    end

    it "accepts full current-period coverage by an exactly adjoining paid recurring chain" do
      advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
      legacy_connection.execute("UPDATE billing_invoices SET period_end = '2026-10-15 12:00:00' WHERE id = 31")
      invoice(id: 32, status: "paid", number: "INV-4001-00009", paid_at: "2026-10-15 13:00:00",
              period_start: "2026-10-15 12:00:00", period_end: "2026-11-01 12:00:00")
      migrate_preserving_window!
    end

    ["2026-10-16 12:00:00", "2026-10-14 12:00:00"].each do |next_start|
      it "fails closed on a paid chain with a gap or ambiguous partial overlap at #{next_start} in the no-intent old schema" do
        advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00")
        legacy_connection.execute("UPDATE billing_invoices SET period_end = '2026-10-15 12:00:00' WHERE id = 31")
        invoice(id: 32, status: "paid", number: "INV-4001-00009", paid_at: "2026-10-16 13:00:00",
                period_start: next_start, period_end: "2026-11-01 12:00:00")
        expect(legacy_connection.table_exists?(:billing_plan_changes)).to be(false)
        reject_preflight!("unpaid_active_current_periods", [20])
      end
    end

    [
      { period_start: "2026-10-02 12:00:00" },
      { period_end: "2026-10-31 12:00:00" },
      { period_start: "2026-11-01 12:00:00", period_end: "2026-12-01 12:00:00" },
      { customer_id: 4002 },
      { currency: "CNY" }
    ].each do |attributes|
      it "refuses incomplete or foreign current-window paid evidence: #{attributes.inspect}" do
        advanced_renewal(status: "paid", paid_at: "2026-10-01 13:00:00", **attributes)
        reject_preflight!("unpaid_active_current_periods", [20])
      end
    end
  end

  it "installs restrictive FKs on the new intent, authorization, attempt and notice tables" do
    migrate_legacy!(described_class)
    expected = {
      billing_plan_changes: %w[customer_id billing_subscription_id from_plan_id to_plan_id],
      billing_coupon_redemptions: %w[customer_id billing_subscription_id billing_coupon_id],
      billing_collection_attempts: %w[customer_id billing_invoice_id payment_id billing_payment_method_id merchant_account_id],
      billing_notices: %w[customer_id billing_invoice_id billing_subscription_id billing_collection_attempt_id],
      billing_invoice_sequences: %w[customer_id],
      billing_payment_methods: %w[customer_id payments_subscription_id merchant_account_id authorized_by_id]
    }
    expected.each do |table, columns|
      keys = legacy_connection.foreign_keys(table)
      expect(keys.map(&:column)).to match_array(columns)
      expect(keys.map(&:on_delete).uniq).to eq([:restrict])
    end
    expect { legacy_insert(:billing_invoice_sequences, customer_id: 999) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { legacy_connection.execute("DELETE FROM billing_subscriptions WHERE id = 20") }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces the widened live uniqueness, permanent request identity and one sequence per customer in SQLite" do
    migrate_legacy!(described_class)
    subscription = legacy_rows(:billing_subscriptions).first
    expect { legacy_insert(:billing_subscriptions, **subscription.except("id").merge("status" => "pending", "request_key" => "new-request")) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { legacy_insert(:billing_subscriptions, **subscription.except("id").merge("status" => "cancelled")) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { legacy_insert(:billing_invoice_sequences, customer_id: 4001) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { legacy_connection.execute("UPDATE billing_invoices SET total_cents = -1 WHERE id = 30") }.to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/)
  end

  it "enforces one outstanding plan change and one proration invoice for its permanent identity" do
    migrate_legacy!(described_class)
    legacy_insert(:billing_plans, id: 11, code: "new-offering", name: "New offering", interval: "monthly", amount_usd: "199.99")
    change = { customer_id: 4001, billing_subscription_id: 20, from_plan_id: 10, to_plan_id: 11, request_key: "change-1",
               kind: "immediate", status: "awaiting_payment", effective_at: "2026-02-14 12:00:00",
               period_start: "2026-01-31 12:00:00", period_end: "2026-02-28 12:00:00" }
    change_id = legacy_insert(:billing_plan_changes, **change)
    expect { legacy_insert(:billing_plan_changes, **change.merge(request_key: "change-2")) }.to raise_error(ActiveRecord::RecordNotUnique)
    invoice(id: 31, status: "open", purpose: "proration", billing_plan_change_id: change_id, idempotency_key: "proration-1")
    expect { invoice(id: 32, status: "open", purpose: "proration", billing_plan_change_id: change_id, idempotency_key: "proration-2") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { legacy_connection.execute("DELETE FROM billing_plan_changes WHERE id = #{change_id}") }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces one inflight attempt, permanent attempt keys and ordinals without destroying completed attempts" do
    mandate(id: 50)
    billing_method
    legacy_insert(:payment_merchant_accounts, id: 80, customer_id: 81721200, provider: "alipay", merchant_id: "platform-account")
    migrate_legacy!(described_class)
    attempt = { id: 100, customer_id: 4001, billing_invoice_id: 30, ordinal: 1, billing_payment_method_id: 60,
                merchant_account_id: 80, state: "pending", request_key: "attempt-1" }
    legacy_insert(:billing_collection_attempts, **attempt)
    expect { legacy_insert(:billing_collection_attempts, **attempt.merge(id: 101, ordinal: 2, request_key: "attempt-2")) }.to raise_error(ActiveRecord::RecordNotUnique)
    legacy_connection.execute("UPDATE billing_collection_attempts SET state = 'failed' WHERE id = 100")
    expect { legacy_insert(:billing_collection_attempts, **attempt.merge(id: 101, request_key: "attempt-2")) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { legacy_insert(:billing_collection_attempts, **attempt.merge(id: 101, ordinal: 2)) }.to raise_error(ActiveRecord::RecordNotUnique)
    legacy_insert(:billing_collection_attempts, **attempt.merge(id: 101, ordinal: 2, request_key: "attempt-2"))
    expect(legacy_rows(:billing_collection_attempts).map { |row| row.slice("ordinal", "state") }).to eq(
      [{ "ordinal" => 1, "state" => "failed" }, { "ordinal" => 2, "state" => "pending" }])
    expect { legacy_connection.execute("DELETE FROM billing_payment_methods WHERE id = 60") }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces unique catalog defaults, redemption cycles and mandate ownership links in the migrated database" do
    mandate(id: 50)
    billing_method
    legacy_insert(:billing_coupons, id: 70, code: "reserved", name: "Reserved coupon", discount_type: "percent", percent_off: 10, duration: "forever")
    migrate_legacy!(described_class)
    legacy_insert(:billing_plans, id: 11, code: "default-1", name: "Free default", interval: "monthly", is_default: true)
    expect { legacy_insert(:billing_plans, id: 12, code: "default-2", name: "Other default", interval: "monthly", is_default: true) }.to raise_error(ActiveRecord::RecordNotUnique)
    redemption = { id: 71, customer_id: 4001, billing_subscription_id: 20, billing_coupon_id: 70, redeemed_at: "2026-01-31 12:00:00" }
    legacy_insert(:billing_coupon_redemptions, **redemption)
    expect { legacy_insert(:billing_coupon_redemptions, **redemption.merge(id: 72)) }.to raise_error(ActiveRecord::RecordNotUnique)
    legacy_connection.execute("UPDATE billing_invoices SET billing_coupon_redemption_id = 71, coupon_cycle_number = 1 WHERE id = 30")
    expect { invoice(id: 31, status: "open", purpose: "renewal", idempotency_key: "next-cycle", billing_coupon_redemption_id: 71, coupon_cycle_number: 1) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { billing_method(id: 61, customer_id: 4002, request_key: "other-method") }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "refuses rollback rather than discarding accepted financial identities" do
    migrate_legacy!(described_class)
    schema = legacy_schema_state
    expect { migrate_legacy!(described_class, direction: :down) }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(legacy_schema_state).to eq(schema)
  end
end
