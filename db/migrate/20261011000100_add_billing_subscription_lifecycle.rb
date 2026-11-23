# frozen_string_literal: true

require "digest"
require "json"
require "bigdecimal"

# Consolidated A/B schema foundation. No provider calls or application-model
# callbacks. Run billing:repair_report BEFORE authorizing this migration.
class AddBillingSubscriptionLifecycle < ActiveRecord::Migration[8.1]
  CORE_KEYS = %w[page entity member].freeze

  def self.report(connection)
    findings = {}
    pairs = {
      "billing_subscriptions" => { "customer_id" => "customers", "billing_plan_id" => "billing_plans", "billing_coupon_id" => "billing_coupons" },
      "billing_invoices" => { "customer_id" => "customers", "billing_subscription_id" => "billing_subscriptions", "billing_coupon_id" => "billing_coupons", "payment_id" => "payments" },
      "billing_invoice_line_items" => { "customer_id" => "customers", "billing_invoice_id" => "billing_invoices" },
      "billing_payment_methods" => { "customer_id" => "customers", "payments_subscription_id" => "payment_subscriptions" }
    }
    pairs.each do |table, columns|
      columns.each do |column, parent|
        rows = connection.select_values("SELECT t.id FROM #{table} t LEFT JOIN #{parent} p ON p.id = t.#{column} WHERE t.#{column} IS NOT NULL AND p.id IS NULL")
        findings["orphan:#{table}.#{column}"] = rows if rows.any?
      end
    end
    queries = {
      "duplicate_live_customers" => "SELECT customer_id FROM billing_subscriptions WHERE status IN ('pending','trialing','active','past_due','paused') GROUP BY customer_id HAVING COUNT(*) > 1",
      "duplicate_defaults" => "SELECT id FROM billing_plans WHERE is_default = 1 AND (SELECT COUNT(*) FROM billing_plans WHERE is_default = 1) > 1",
      "invalid_default_plan" => "SELECT id FROM billing_plans WHERE is_default = 1 AND (active != 1 OR amount_usd != 0 OR amount_cny != 0 OR trial_days != 0)",
      "invalid_default_limits" => "SELECT p.id FROM billing_plans p WHERE p.is_default = 1 AND ((SELECT COUNT(*) FROM billing_plan_limits l WHERE l.billing_plan_id = p.id AND l.item_key IN ('page','entity','member') AND l.limit_value >= 0) != 3)",
      "invalid_invoice_amounts" => "SELECT id FROM billing_invoices WHERE subtotal_cents < 0 OR discount_cents < 0 OR tax_cents < 0 OR total_cents < 0 OR attempt_count < 0",
      "invalid_catalog_amounts" => "SELECT id FROM billing_plans WHERE amount_usd < 0 OR amount_cny < 0 OR trial_days < 0",
      "invalid_plan_limits" => "SELECT id FROM billing_plan_limits WHERE limit_value < -1",
      "invalid_coupon_terms" => "SELECT id FROM billing_coupons WHERE times_redeemed < 0 OR discount_type NOT IN ('percent','fixed') OR duration NOT IN ('once','repeating','forever') OR (discount_type = 'percent' AND (percent_off IS NULL OR percent_off NOT BETWEEN 1 AND 100)) OR (discount_type = 'fixed' AND (amount_off_cents IS NULL OR amount_off_cents <= 0)) OR (duration = 'repeating' AND (duration_in_cycles IS NULL OR duration_in_cycles <= 0)) OR (max_redemptions IS NOT NULL AND max_redemptions <= 0)",
      "duplicate_method_defaults" => "SELECT customer_id FROM billing_payment_methods WHERE is_default = 1 AND status = 'active' GROUP BY customer_id HAVING COUNT(*) > 1",
      "duplicate_invoice_numbers" => "SELECT number FROM billing_invoices WHERE number IS NOT NULL GROUP BY number HAVING COUNT(*) > 1",
      "invoice_tenant_mismatch" => "SELECT i.id FROM billing_invoices i JOIN billing_subscriptions s ON s.id = i.billing_subscription_id WHERE i.customer_id != s.customer_id OR i.currency != s.currency",
      "invoice_missing_dates" => "SELECT id FROM billing_invoices WHERE period_start IS NULL OR period_end IS NULL OR (status != 'draft' AND due_at IS NULL)",
      "line_tenant_mismatch" => "SELECT l.id FROM billing_invoice_line_items l JOIN billing_invoices i ON i.id = l.billing_invoice_id WHERE l.customer_id != i.customer_id",
      "unsupported_subscription_currency" => "SELECT id FROM billing_subscriptions WHERE currency NOT IN ('USD','CNY')",
      "invalid_periods" => "SELECT id FROM billing_subscriptions WHERE current_period_start IS NULL OR current_period_end IS NULL OR current_period_end <= current_period_start",
      "invalid_mandate_links" => "SELECT m.id FROM billing_payment_methods m JOIN payment_subscriptions s ON s.id = m.payments_subscription_id WHERE s.customer_id != 81721200 OR s.provider != m.provider",
      "shared_mandates" => "SELECT payments_subscription_id FROM billing_payment_methods WHERE payments_subscription_id IS NOT NULL GROUP BY payments_subscription_id HAVING COUNT(*) > 1",
      "unmapped_billing_mandates" => "SELECT s.id FROM payment_subscriptions s LEFT JOIN billing_payment_methods m ON m.payments_subscription_id = s.id WHERE s.external_ref LIKE 'billing-pm-%' AND m.id IS NULL",
      "unfinished_billing_collections" => "SELECT p.id FROM payments p JOIN payment_orders o ON o.id = p.payment_order_id WHERE o.external_ref LIKE 'billing-inv-%' AND p.status IN ('created','pending')",
      "unprojected_captures" => "SELECT p.id FROM payments p JOIN payment_orders o ON o.id = p.payment_order_id LEFT JOIN billing_invoices i ON o.external_ref = 'billing-inv-' || i.id WHERE o.external_ref LIKE 'billing-inv-%' AND p.status = 'succeeded' AND (i.id IS NULL OR i.status != 'paid')",
      "unused_subscription_mandate_links" => "SELECT id FROM billing_subscriptions WHERE payments_subscription_id IS NOT NULL",
      "invalid_fixed_coupons" => "SELECT id FROM billing_coupons WHERE discount_type = 'fixed' AND (currency IS NULL OR currency NOT IN ('USD','CNY'))"
    }
    queries.delete("unused_subscription_mandate_links") unless connection.column_exists?(:billing_subscriptions, :payments_subscription_id)
    unless connection.table_exists?(:billing_coupon_redemptions)
      queries["unknown_historical_coupon_cycles"] = "SELECT DISTINCT s.id FROM billing_subscriptions s JOIN billing_invoices i ON i.billing_subscription_id = s.id WHERE s.billing_coupon_id IS NOT NULL AND i.status != 'draft' AND i.subtotal_cents > 0"
    end
    if connection.column_exists?(:billing_payment_methods, :merchant_account_id)
      queries["historical_authorization_review"] = "SELECT id FROM billing_payment_methods WHERE status != 'removed' AND (merchant_account_id IS NULL OR failure_code = 'historical_authorization_review')"
    end
    original_trial = ongoing_original_trial_sql(connection)
    # An unpaid first cycle cannot justify the legacy active purchased snapshot.
    # A paid recurring cycle (including genuinely settled zero/manual invoices)
    # is evidence; today's catalog price and a draft's default zero total are not.
    queries["unpaid_active_initial_intents"] = <<~SQL.squish
      SELECT DISTINCT s.id
      FROM billing_subscriptions s
      WHERE s.status = 'active' AND s.amount_cents > 0 AND NOT (#{original_trial})
        AND NOT EXISTS (
          SELECT 1 FROM billing_invoices settled
          WHERE settled.billing_subscription_id = s.id
            AND settled.customer_id = s.customer_id AND settled.currency = s.currency
            AND settled.status = 'paid'
            AND NOT EXISTS (
              SELECT 1 FROM billing_invoice_line_items l
              WHERE l.billing_invoice_id = settled.id AND l.kind = 'proration'
            )
        )
      ORDER BY s.id
    SQL
    # Legacy renewal advanced dates BEFORE collection. Any historical paid base
    # is therefore insufficient: prove the whole stored period, without changing
    # dates/status/debt. A containing paid window or exactly adjoining recurring
    # windows is evidence; partial overlaps cannot establish an unrecorded intent.
    # On the current schema, explicit invoice purpose is authoritative. Proration
    # payment alone never purchases a recurring base, even with an applied target.
    recurring_purpose = connection.column_exists?(:billing_invoices, :purpose) ? "AND i.purpose IN ('initial','renewal')" : ""
    queries["unpaid_active_current_periods"] = <<~SQL.squish
      WITH RECURSIVE paid_recurring AS (
        SELECT i.billing_subscription_id, i.customer_id, i.currency, i.period_start, i.period_end
        FROM billing_invoices i
        WHERE i.status = 'paid' AND i.period_end > i.period_start
          #{recurring_purpose}
          AND NOT EXISTS (
            SELECT 1 FROM billing_invoice_line_items l
            WHERE l.billing_invoice_id = i.id AND l.kind = 'proration'
          )
      ), covered (subscription_id, covered_end) AS (
        SELECT s.id, i.period_end
        FROM billing_subscriptions s JOIN paid_recurring i
          ON i.billing_subscription_id = s.id AND i.customer_id = s.customer_id AND i.currency = s.currency
        WHERE s.status = 'active' AND s.amount_cents > 0 AND NOT (#{original_trial})
          AND i.period_start <= s.current_period_start AND i.period_end > s.current_period_start
        UNION
        SELECT c.subscription_id, i.period_end
        FROM covered c JOIN billing_subscriptions s ON s.id = c.subscription_id
          JOIN paid_recurring i ON i.billing_subscription_id = s.id
            AND i.customer_id = s.customer_id AND i.currency = s.currency
        WHERE i.period_start = c.covered_end AND c.covered_end < s.current_period_end
      )
      SELECT s.id FROM billing_subscriptions s
      WHERE s.status = 'active' AND s.amount_cents > 0 AND NOT (#{original_trial})
        AND NOT EXISTS (
          SELECT 1 FROM covered c WHERE c.subscription_id = s.id AND c.covered_end >= s.current_period_end
        )
      ORDER BY s.id
    SQL
    intent_check = ""
    if connection.table_exists?(:billing_plan_changes) && connection.column_exists?(:billing_invoices, :billing_plan_change_id)
      intent_check = <<~SQL.squish
        AND NOT EXISTS (
          SELECT 1 FROM billing_plan_changes c
          WHERE c.id = i.billing_plan_change_id AND c.customer_id = i.customer_id
            AND c.billing_subscription_id = i.billing_subscription_id AND c.kind = 'immediate'
            AND c.period_start = i.period_start AND c.period_end = i.period_end
        )
      SQL
    end
    queries["unresolved_proration_intents"] = <<~SQL.squish
      SELECT DISTINCT i.id FROM billing_invoices i
      WHERE i.status IN ('draft','open','uncollectible')
        AND EXISTS (
          SELECT 1 FROM billing_invoice_line_items l
          WHERE l.billing_invoice_id = i.id AND l.kind = 'proration'
        )
        #{intent_check}
      ORDER BY i.id
    SQL
    queries.each do |key, sql|
      rows = connection.select_values(sql)
      findings[key] = rows if rows.any?
    end
    payment_conflicts = invoice_payment_conflicts(connection)
    if payment_conflicts.any?
      findings["invoice_payment_mismatch"] = payment_conflicts.map { |row| row.fetch("invoice_id") }
      findings["invoice_payment_mismatch_evidence"] = payment_conflicts
    end
    findings
  end

  # Read-only bulk join against the explicit historical FK. Missing links on
  # paid manual/zero invoices are valid ledger history; a present link must not
  # contradict platform ownership, operation identity, currency or either amount.
  # No account resolver, application callbacks, PSP query or guessed replacement.
  def self.invoice_payment_conflicts(connection)
    rows = connection.select_all(<<~SQL.squish).to_a
      SELECT i.id AS invoice_id, i.payment_id, i.status AS invoice_status,
        i.currency AS invoice_currency, i.total_cents,
        p.id AS linked_payment_id, p.customer_id AS payment_customer_id,
        p.payment_order_id AS order_id, p.status AS payment_status,
        CAST(p.amount AS TEXT) AS payment_amount,
        o.id AS linked_order_id, o.customer_id AS order_customer_id,
        o.external_ref, o.currency AS order_currency, CAST(o.amount AS TEXT) AS order_amount
      FROM billing_invoices i
      LEFT JOIN payments p ON p.id = i.payment_id
      LEFT JOIN payment_orders o ON o.id = p.payment_order_id
      WHERE i.payment_id IS NOT NULL
      ORDER BY i.id
    SQL
    rows.filter_map do |row|
      reasons = []
      reasons << "payment_missing" unless row["linked_payment_id"]
      reasons << "order_missing" unless row["linked_order_id"]
      reasons << "payment_owner_mismatch" unless row["payment_customer_id"] == 81_721_200
      reasons << "order_owner_mismatch" unless row["order_customer_id"] == 81_721_200
      reasons << "order_reference_mismatch" unless row["external_ref"] == "billing-inv-#{row['invoice_id']}"
      reasons << "currency_mismatch" unless row["order_currency"] == row["invoice_currency"]
      reasons << "payment_amount_mismatch" unless minor_amount_matches?(row["payment_amount"], row["total_cents"])
      reasons << "order_amount_mismatch" unless minor_amount_matches?(row["order_amount"], row["total_cents"])
      reasons << "capture_not_succeeded" if row["invoice_status"] == "paid" && row["payment_status"] != "succeeded"
      next if reasons.empty?

      row.slice("invoice_id", "payment_id", "order_id").merge("reasons" => reasons)
    end
  end

  def self.minor_amount_matches?(amount, expected)
    return false if amount.nil? || expected.nil?
    decimal = BigDecimal(amount, exception: false)
    decimal && decimal.finite? && decimal >= 0 && decimal * 100 == expected
  end

  def self.ongoing_original_trial_sql(connection)
    # trial_end is retained after renewal; its mere presence is not a waiver.
    # Only the original, unadvanced, still-ongoing trial needs no paid invoice.
    now = connection.quote(Time.current)
    <<~SQL.squish
      s.trial_end IS NOT NULL AND s.started_at IS NOT NULL
        AND s.current_period_start = s.started_at AND s.current_period_end = s.trial_end
        AND s.trial_end > s.current_period_start AND s.current_period_start <= #{now} AND s.trial_end > #{now}
    SQL
  end
  private_class_method :invoice_payment_conflicts, :minor_amount_matches?, :ongoing_original_trial_sql

  def up
    conflicts = self.class.report(connection)
    raise ActiveRecord::MigrationError, "Billing preflight conflicts: #{JSON.generate(conflicts)}" if conflicts.any?

    add_column :customers, :trial_used_at, :datetime
    add_column :billing_plans, :archived_at, :datetime
    add_column :billing_coupons, :archived_at, :datetime
    add_index :billing_plans, :is_default, unique: true, where: "is_default = 1", name: "billing_one_default_plan"
    add_column :billing_subscriptions, :request_key, :string
    add_column :billing_subscriptions, :plan_snapshot, :json, null: false, default: {}
    add_column :billing_subscriptions, :billing_anchor_day, :integer
    add_column :billing_subscriptions, :billing_anchor_month, :integer
    remove_column :billing_subscriptions, :payments_subscription_id, :bigint
    remove_index :billing_subscriptions, name: "index_billing_subscriptions_on_customer_id_live_unique"
    add_index :billing_subscriptions, :customer_id, unique: true,
      where: "status IN ('pending','trialing','active','past_due','paused')", name: "index_billing_subscriptions_on_customer_id_live_unique"
    add_index :billing_subscriptions, %i[customer_id request_key], unique: true, name: "billing_subscription_request_identity"

    create_table :billing_plan_changes do |t|
      t.bigint :customer_id, null: false
      t.bigint :billing_subscription_id, null: false
      t.bigint :from_plan_id, null: false
      t.bigint :to_plan_id, null: false
      t.string :request_key, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.datetime :effective_at, null: false
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.json :from_snapshot, null: false, default: {}
      t.json :target_snapshot, null: false, default: {}
      t.datetime :applied_at
      t.datetime :cancelled_at
      t.timestamps
      t.index %i[customer_id request_key], unique: true, name: "billing_change_request_identity"
      t.index :billing_subscription_id, unique: true, where: "status IN ('awaiting_payment','scheduled')", name: "billing_one_outstanding_change"
      t.index :from_plan_id
      t.index :to_plan_id
    end
    create_table :billing_coupon_redemptions do |t|
      t.bigint :customer_id, null: false, index: true
      t.bigint :billing_subscription_id, null: false, index: { unique: true }
      t.bigint :billing_coupon_id, null: false, index: true
      t.json :terms_snapshot, null: false, default: {}
      t.datetime :redeemed_at, null: false
      t.integer :cycles_used, null: false, default: 0
      t.timestamps
    end

    invoice_schema
    authorization_schema
    backfill
    integrity
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Accepted billing intents and financial identities cannot be discarded"
  end

  private

  def invoice_schema
    change_table :billing_invoices do |t|
      t.string :purpose
      t.string :idempotency_key
      t.bigint :billing_plan_change_id
      t.bigint :billing_coupon_redemption_id
      t.integer :coupon_cycle_number
      t.json :terms_snapshot, null: false, default: {}
      t.string :collection_state, null: false, default: "ready"
      t.datetime :first_failed_at
      t.datetime :collection_claimed_at
      t.string :failure_code
      t.string :settlement_review_code
      t.string :settlement_source
      t.bigint :settled_by_id
      t.string :settlement_reference
      t.text :settlement_note
      t.string :collection_override_mode
      t.bigint :collection_override_by_id
      t.datetime :collection_override_at
      # A settlement projection receipt is independent of payment status. It
      # makes a redriven hook distinguish applied intent from a stale period.
      t.datetime :entitlements_applied_at
    end
    add_index :billing_invoices, %i[customer_id idempotency_key], unique: true, name: "billing_invoice_request_identity"
    add_index :billing_invoices, :billing_plan_change_id, unique: true, where: "purpose = 'proration'", name: "billing_one_proration_per_change"
    add_index :billing_invoices, %i[billing_coupon_redemption_id coupon_cycle_number], unique: true,
      where: "coupon_cycle_number IS NOT NULL", name: "billing_one_invoice_per_coupon_cycle"
    add_index :billing_invoices, %i[collection_state next_attempt_at], name: "billing_collection_population"
    create_table :billing_invoice_sequences do |t|
      t.bigint :customer_id, null: false, index: { unique: true }
      t.bigint :last_value, null: false, default: 0
      t.timestamps
    end
    create_table :billing_collection_attempts do |t|
      t.bigint :customer_id, null: false, index: true
      t.bigint :billing_invoice_id, null: false
      t.integer :ordinal, null: false
      t.bigint :payment_id
      t.bigint :billing_payment_method_id, null: false, index: true
      t.bigint :merchant_account_id, null: false, index: true
      t.string :state, null: false, default: "prepared"
      t.string :request_key, null: false, index: { unique: true }
      t.string :failure_code
      t.datetime :submitted_at
      t.datetime :completed_at
      t.datetime :reconcile_at
      t.datetime :claimed_at
      t.timestamps
      t.index %i[billing_invoice_id ordinal], unique: true, name: "billing_attempt_ordinal"
      t.index :payment_id, unique: true, where: "payment_id IS NOT NULL"
      t.index :billing_invoice_id, unique: true, where: "state IN ('prepared','submitting','pending','requires_action','unknown')", name: "billing_one_inflight_attempt"
    end
    create_table :billing_notices do |t|
      t.bigint :customer_id, null: false, index: true
      t.string :event_key, null: false, index: { unique: true }
      t.string :kind, null: false
      t.bigint :billing_invoice_id, index: true
      t.bigint :billing_subscription_id, index: true
      t.bigint :billing_collection_attempt_id, index: true
      t.string :state, null: false, default: "pending"
      t.datetime :enqueued_at
      t.timestamps
    end
    remove_column :billing_settings, :gateway_provider, :string
  end

  def authorization_schema
    change_table :billing_payment_methods do |t|
      t.string :request_key
      t.bigint :merchant_account_id
      t.bigint :authorized_by_id
      t.string :authorization_reference
      t.datetime :authorization_expires_at
      t.boolean :requested_default, null: false, default: false
      t.datetime :removed_at
      t.string :revocation_state, null: false, default: "none"
      t.datetime :revocation_next_attempt_at
      t.integer :revocation_attempt_count, null: false, default: 0
      t.string :failure_code
    end
    add_index :billing_payment_methods, %i[customer_id request_key], unique: true, name: "billing_method_request_identity"
    remove_index :billing_payment_methods, :payments_subscription_id
    add_index :billing_payment_methods, :payments_subscription_id, unique: true, where: "payments_subscription_id IS NOT NULL", name: "billing_one_method_per_mandate"
    add_index :billing_payment_methods, %i[merchant_account_id authorization_reference], unique: true,
      where: "authorization_reference IS NOT NULL", name: "billing_authorization_identity"
    add_column :payment_subscriptions, :managed_by, :string, null: false, default: "payments"
    # Provider correlation data only. managed_by remains the ownership authority.
    add_column :payment_subscriptions, :metadata, :json, null: false, default: {}
    add_index :payment_subscriptions, %i[managed_by status next_charge_at], name: "payment_subscription_collection_owner"
    add_column :payment_methods, :billing_customer_id, :bigint
    add_column :payment_methods, :billing_authorized_by_id, :bigint
    change_column_null :payment_methods, :user_id, true
    add_index :payment_methods, :billing_customer_id
  end

  def backfill
    policy = select_one("SELECT * FROM billing_settings WHERE singleton_guard = 0") || {}
    policy = { "tax_rate_bps" => policy.fetch("tax_rate_bps", 0), "grace_period_days" => policy.fetch("grace_period_days", 7),
      "collection_mode" => policy.fetch("collection_mode", "manual"), "dunning_schedule" => JSON.parse(policy["dunning_schedule"] || "[1,3,7]") }
    select_all("SELECT * FROM billing_subscriptions").each do |subscription|
      id = subscription.fetch("id")
      plan = select_one("SELECT * FROM billing_plans WHERE id = #{id_number(subscription['billing_plan_id'])}")
      limits = select_all("SELECT item_key, limit_value FROM billing_plan_limits WHERE billing_plan_id = #{id_number(plan['id'])}").to_h { |row| [row['item_key'], row['limit_value']] }
      snapshot = { "plan_id" => plan["id"], "code" => plan["code"], "name" => plan["name"],
        "amount_cents" => subscription["amount_cents"], "currency" => subscription["currency"], "interval" => subscription["interval"],
        "limits" => CORE_KEYS.to_h { |key| [key, limits.fetch(key, 0)] }, "grace_period_days" => policy["grace_period_days"], "reconstructed" => true }
      start = Time.parse(subscription.fetch("current_period_start").to_s)
      execute "UPDATE billing_subscriptions SET request_key = #{quote(request_key('subscription', id))}, plan_snapshot = #{quote(JSON.generate(snapshot))}, billing_anchor_day = #{start.day}, billing_anchor_month = #{start.month} WHERE id = #{id_number(id)}"
      if subscription["trial_end"]
        used = subscription["started_at"] || subscription["created_at"]
        execute "UPDATE customers SET trial_used_at = #{quote(used)} WHERE id = #{id_number(subscription['customer_id'])} AND (trial_used_at IS NULL OR trial_used_at > #{quote(used)})"
      end
      if subscription["billing_coupon_id"]
        coupon = select_one("SELECT * FROM billing_coupons WHERE id = #{id_number(subscription['billing_coupon_id'])}")
        terms = coupon.slice("code", "name", "discount_type", "percent_off", "amount_off_cents", "currency", "duration", "duration_in_cycles")
        execute "INSERT INTO billing_coupon_redemptions (customer_id,billing_subscription_id,billing_coupon_id,terms_snapshot,redeemed_at,cycles_used,created_at,updated_at) VALUES (#{id_number(subscription['customer_id'])},#{id_number(id)},#{id_number(coupon['id'])},#{quote(JSON.generate(terms))},#{quote(subscription['created_at'])},0,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)"
      end
      select_all("SELECT * FROM billing_invoices WHERE billing_subscription_id = #{id_number(id)} ORDER BY period_start, id").each_with_index do |invoice, position|
        proration = select_value("SELECT COUNT(*) FROM billing_invoice_line_items WHERE billing_invoice_id = #{id_number(invoice['id'])} AND kind = 'proration'").to_i.positive?
        purpose = proration ? "proration" : (position.zero? && !subscription["trial_end"] ? "initial" : "renewal")
        terms = snapshot.merge(policy).merge("collection_mode" => invoice["collection_mode"] || policy["collection_mode"],
          "due_at" => Time.parse((invoice["due_at"] || invoice["period_start"]).to_s).utc.iso8601(6), "billing_anchor_day" => start.day, "billing_anchor_month" => start.month)
        state = case invoice["status"]
        when "paid" then "settled"
        when "void" then "stopped"
        when "uncollectible" then "exhausted"
        else terms["collection_mode"] == "manual" ? "manual" : (invoice["attempt_count"].to_i.positive? ? "blocked" : "ready")
        end
        receipt = invoice["status"] == "paid" ? invoice["paid_at"] || invoice["updated_at"] : nil
        execute "UPDATE billing_invoices SET purpose = #{quote(purpose)}, idempotency_key = #{quote("historical:#{invoice['id']}")}, terms_snapshot = #{quote(JSON.generate(terms))}, due_at = COALESCE(due_at, period_start), collection_state = #{quote(state)}, entitlements_applied_at = #{quote(receipt)} WHERE id = #{id_number(invoice['id'])}"
      end
      say "Reconstructed subscription #{id} and invoice policy from stored amounts and current catalog; historical lines retained"
    end
    select_all("SELECT * FROM billing_payment_methods").each do |method|
      execute "UPDATE billing_payment_methods SET request_key = #{quote(request_key('method', method['id']))} WHERE id = #{id_number(method['id'])}"
      if method["payments_subscription_id"]
        metadata = { "billing_owned" => true, "billing_payment_method_id" => method["id"], "billing_customer_id" => method["customer_id"] }
        execute "UPDATE payment_subscriptions SET managed_by = 'billing', metadata = #{quote(JSON.generate(metadata))}, next_charge_at = NULL, charge_claimed_at = NULL WHERE id = #{id_number(method['payments_subscription_id'])}"
      end
      # Historical authorization accounts cannot be inferred from current mode.
      # Keep methods blocked until exact provider/account proof is established.
      execute "UPDATE billing_payment_methods SET failure_code = 'historical_authorization_review' WHERE id = #{id_number(method['id'])}"
    end
    select_values("SELECT DISTINCT customer_id FROM billing_invoices").each do |customer_id|
      maximum = select_values("SELECT number FROM billing_invoices WHERE customer_id = #{id_number(customer_id)} AND number IS NOT NULL").filter_map do |number|
        match = /\AINV-#{customer_id}-(\d+)\z/.match(number)
        match && match[1].to_i
      end.max || 0
      execute "INSERT INTO billing_invoice_sequences (customer_id,last_value,created_at,updated_at) VALUES (#{id_number(customer_id)},#{maximum},CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)"
    end
    execute "UPDATE billing_countable_items SET enabled = 0 WHERE key NOT IN ('page','entity','member')"
    change_column_null :billing_subscriptions, :request_key, false
    change_column_null :billing_invoices, :purpose, false
    change_column_null :billing_invoices, :idempotency_key, false
    change_column_null :billing_payment_methods, :request_key, false
  end

  def integrity
    foreign_keys = {
      billing_subscriptions: { customer_id: :customers, billing_plan_id: :billing_plans, billing_coupon_id: :billing_coupons },
      billing_invoices: { customer_id: :customers, billing_subscription_id: :billing_subscriptions, billing_coupon_id: :billing_coupons,
        billing_plan_change_id: :billing_plan_changes, billing_coupon_redemption_id: :billing_coupon_redemptions,
        payment_id: :payments, settled_by_id: :users, collection_override_by_id: :users },
      billing_invoice_line_items: { customer_id: :customers, billing_invoice_id: :billing_invoices },
      billing_plan_changes: { customer_id: :customers, billing_subscription_id: :billing_subscriptions, from_plan_id: :billing_plans, to_plan_id: :billing_plans },
      billing_coupon_redemptions: { customer_id: :customers, billing_subscription_id: :billing_subscriptions, billing_coupon_id: :billing_coupons },
      billing_payment_methods: { customer_id: :customers, payments_subscription_id: :payment_subscriptions, merchant_account_id: :payment_merchant_accounts, authorized_by_id: :users },
      billing_invoice_sequences: { customer_id: :customers },
      billing_collection_attempts: { customer_id: :customers, billing_invoice_id: :billing_invoices, payment_id: :payments,
        billing_payment_method_id: :billing_payment_methods, merchant_account_id: :payment_merchant_accounts },
      billing_notices: { customer_id: :customers, billing_invoice_id: :billing_invoices, billing_subscription_id: :billing_subscriptions, billing_collection_attempt_id: :billing_collection_attempts },
      payment_methods: { billing_customer_id: :customers, billing_authorized_by_id: :users }
    }
    foreign_keys.each { |table, columns| columns.each { |column, parent| add_foreign_key table, parent, column: column, on_delete: :restrict } }
    checks = {
      billing_subscriptions: ["amount_cents >= 0", "status IN ('pending','trialing','active','past_due','paused','cancelled','expired')", "currency IN ('USD','CNY')", "interval IN ('monthly','yearly')", "billing_anchor_day BETWEEN 1 AND 31 AND billing_anchor_month BETWEEN 1 AND 12"],
      billing_plans: ["amount_usd >= 0 AND amount_cny >= 0 AND trial_days >= 0", "is_default = 0 OR (active = 1 AND archived_at IS NULL AND amount_usd = 0 AND amount_cny = 0 AND trial_days = 0)"],
      billing_plan_limits: ["limit_value >= -1"],
      billing_coupons: ["times_redeemed >= 0", "discount_type != 'fixed' OR (currency IS NOT NULL AND currency IN ('USD','CNY'))",
        "discount_type IN ('percent','fixed') AND duration IN ('once','repeating','forever')",
        "discount_type != 'percent' OR (percent_off IS NOT NULL AND percent_off BETWEEN 1 AND 100)",
        "discount_type != 'fixed' OR (amount_off_cents IS NOT NULL AND amount_off_cents > 0)",
        "duration != 'repeating' OR (duration_in_cycles IS NOT NULL AND duration_in_cycles > 0)",
        "max_redemptions IS NULL OR max_redemptions > 0"],
      billing_coupon_redemptions: ["cycles_used >= 0"],
      billing_plan_changes: ["kind IN ('immediate','scheduled')", "status IN ('awaiting_payment','scheduled','applied','cancelled','expired')", "period_end > period_start"],
      billing_invoices: ["subtotal_cents >= 0 AND discount_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0 AND attempt_count >= 0", "purpose IN ('initial','renewal','proration')", "collection_state IN ('ready','manual','blocked','pending','requires_action','retry_wait','exhausted','settled','stopped')", "status IN ('draft','open','paid','void','uncollectible')", "coupon_cycle_number IS NULL OR coupon_cycle_number > 0"],
      billing_invoice_sequences: ["last_value >= 0"],
      billing_collection_attempts: ["ordinal > 0", "state IN ('prepared','submitting','pending','requires_action','succeeded','failed','unknown')"],
      billing_payment_methods: ["revocation_attempt_count >= 0", "status IN ('pending','active','failed','removed')", "revocation_state IN ('none','pending','complete','failed')"],
      billing_notices: ["state IN ('pending','enqueued')"],
      payment_subscriptions: ["managed_by IN ('payments','billing')", "managed_by != 'billing' OR next_charge_at IS NULL"],
      payment_methods: ["(user_id IS NOT NULL AND billing_customer_id IS NULL AND billing_authorized_by_id IS NULL) OR (user_id IS NULL AND customer_id = 81721200 AND billing_customer_id IS NOT NULL AND billing_authorized_by_id IS NOT NULL)"],
      billing_settings: ["tax_rate_bps BETWEEN 0 AND 10000 AND grace_period_days >= 0 AND trial_ending_notice_days >= 0"]
    }
    checks.each { |table, expressions| expressions.each_with_index { |expression, i| add_check_constraint table, expression, name: "#{table}_integrity_#{i}" } }
  end

  def request_key(kind, id)
    digest = Digest::SHA256.hexdigest("billing-historical:#{kind}:#{id}")[0, 32]
    [digest[0, 8], digest[8, 4], digest[12, 4], digest[16, 4], digest[20, 12]].join("-")
  end

  def id_number(value) = Integer(value)
  def quote(value) = connection.quote(value)
end
