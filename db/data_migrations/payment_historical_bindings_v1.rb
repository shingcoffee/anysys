# frozen_string_literal: true

require "active_record"
require "json"

# Offline, versioned data repair, never a request-time compatibility path.
# No application callbacks, credentials, provider requests or financial state
# transitions run here. Only explicit persisted merchant/operation evidence is
# sufficient; a sole tenant/provider account is NOT evidence.
class PaymentHistoricalBindingsV1
  class PaymentRow < ActiveRecord::Base
    self.table_name = "payments"
  end

  class EventRow < ActiveRecord::Base
    self.table_name = "payment_webhook_events"
  end

  class AccountRow < ActiveRecord::Base
    self.table_name = "payment_merchant_accounts"
  end

  class UnresolvedBindings < StandardError
    attr_reader :report

    def initialize(report)
      @report = report
      super("historical payment bindings require explicit merchant evidence; run payments:historical_bindings:preflight")
    end
  end

  def call(apply: false)
    @plans = []
    @unresolved = []
    @event_evidence = Hash.new { |hash, key| hash[key] = [] }
    @summary = { "payments_scanned" => 0, "events_scanned" => 0, "payments_to_bind" => 0, "events_to_bind" => 0 }
    EventRow.find_each { |event| plan_event(event) }
    PaymentRow.find_each { |payment| plan_payment(payment) }
    report = { "summary" => @summary.merge("unresolved" => @unresolved.size), "unresolved" => @unresolved, "applied" => false }
    return report unless apply
    raise UnresolvedBindings.new(report) if @unresolved.any?

    ActiveRecord::Base.transaction do
      @plans.each do |plan|
        row = plan.fetch(:model).find(plan.fetch(:id))
        account = AccountRow.find(plan.fetch(:account_id))
        unchanged = object(row.public_send(plan.fetch(:column))) == plan.fetch(:original) &&
          record_identity(row) == plan.fetch(:record_identity) &&
          [account.provider, account.merchant_id, account.customer_id] == plan.fetch(:account_identity)
        unless unchanged
          problem(plan.fetch(:model) == PaymentRow ? "payment" : "event", row.id, "evidence_changed_after_preflight")
          raise UnresolvedBindings.new(report.merge("unresolved" => @unresolved))
        end

        row.update_columns(plan.fetch(:column) => plan.fetch(:replacement))
      end
    end
    report.merge("applied" => true)
  end

  private

  def plan_event(event)
    @summary["events_scanned"] += 1
    payload = object(event.payload)
    return problem("event", event.id, "invalid_payload") unless payload

    marker = object(payload["_anysys_verification"])
    event_id = event.provider == "alipay" ? payload["notify_id"] : payload["id"]
    if event_id != event.psp_event_id
      return problem("event", event.id, "event_id_conflict")
    end
    account = unique_account(event.provider, event.signing_merchant_id)
    return problem("event", event.id, "missing_or_ambiguous_signing_merchant") unless account
    if event.customer_id.present? && event.customer_id != account.customer_id
      return problem("event", event.id, "customer_conflict")
    end
    if marker && marker["merchant_account_id"].present? && marker["merchant_account_id"] != account.id
      return problem("event", event.id, "existing_verification_conflict")
    end
    refs = references(event.provider, payload)
    refs.each do |kind, ref|
      @event_evidence[[event.provider, kind, ref]] << { merchant_id: account.merchant_id, references: refs }
    end
    return if marker && marker["merchant_account_id"] == account.id

    replacement = payload.merge("_anysys_verification" => { "merchant_account_id" => account.id })
    add_plan(event, :payload, payload, replacement, account)
    @summary["events_to_bind"] += 1
  end

  def plan_payment(payment)
    @summary["payments_scanned"] += 1
    payload = object(payment.prepay_payload)
    return problem("payment", payment.id, "invalid_prepay_payload") unless payload

    context = object(payload["_attempt"]) || {}
    if context["provider"].present? && context["provider"] != payment.provider
      return problem("payment", payment.id, "provider_conflict")
    end
    account = if context["merchant_account_id"].present?
      AccountRow.find_by(id: context["merchant_account_id"], provider: payment.provider, customer_id: payment.customer_id)
    else
      evidence = []
      evidence << context["merchant_id"] if identifier(context["merchant_id"])
      ledger = @event_evidence[[payment.provider, "trade", payment.out_trade_no]].dup
      ledger.concat(@event_evidence[[payment.provider, "psp", payment.psp_transaction_id]]) if payment.psp_transaction_id.present?
      evidence.concat(ledger.select { |entry| compatible_references?(payment, entry.fetch(:references)) }.map { |entry| entry.fetch(:merchant_id) })
      raw = object(payment.raw_notify)
      if raw && compatible_references?(payment, references(payment.provider, raw))
        evidence.concat(merchant_ids(payment.provider, raw))
      end
      mids = evidence.uniq
      mids.one? ? unique_account(payment.provider, mids.first) : nil
    end
    unless account && account.customer_id == payment.customer_id
      return problem("payment", payment.id, "missing_conflicting_or_foreign_merchant_evidence")
    end
    # Existing explicit row identity is authoritative even if its mutable label
    # or mode changed. Complete missing identity keys, never overwrite a pin.
    return if context["merchant_account_id"] == account.id && context["provider"] == payment.provider

    identity = { "provider" => payment.provider, "merchant_account_id" => account.id,
                 "merchant_id" => context["merchant_id"].presence || account.merchant_id,
                 "mode" => context["mode"].presence || account.mode }
    # This is identity recovery, not reconstruction/authorization of an expired
    # financial write. PrepareAttempt rejects the incomplete old write context.
    restored = context.merge(identity).merge("review_reason" => "historical_identity_backfill")
    add_plan(payment, :prepay_payload, payload, payload.merge("_attempt" => restored), account)
    @summary["payments_to_bind"] += 1
  end

  def payment_reference?(payment, kind, ref)
    kind == "trade" ? ref == payment.out_trade_no : ref == payment.psp_transaction_id
  end

  def compatible_references?(payment, refs)
    refs.any? { |kind, ref| payment_reference?(payment, kind, ref) } && refs.all? do |kind, ref|
      kind == "psp" && payment.psp_transaction_id.blank? || payment_reference?(payment, kind, ref)
    end
  end

  def unique_account(provider, merchant_id)
    return nil unless identifier(merchant_id)

    matches = AccountRow.where(provider: provider, merchant_id: merchant_id).limit(2).to_a
    matches.first if matches.one?
  end

  def merchant_ids(provider, payload)
    node = event_object(provider, payload)
    metadata = object(node["metadata"]) || {}
    unit = first_unit(node)
    values = case provider
    when "stripe" then [metadata["merchant_id"], payload["account"]]
    when "alipay" then [node["app_id"]]
    when "wechat_pay" then [node["mchid"]]
    when "paypal" then [node["custom_id"], unit["custom_id"]]
    else []
    end
    values.select { |value| identifier(value) }
  end

  def references(provider, payload)
    node = event_object(provider, payload)
    metadata = object(node["metadata"]) || {}
    unit = first_unit(node)
    related = object(object(node["supplementary_data"]).to_h["related_ids"]) || {}
    capture = object(object(unit["payments"]).to_h.fetch("captures", []).first) || {}
    pairs = case provider
    when "stripe"
      [["trade", metadata["out_trade_no"]], ["psp", node["payment_intent"]],
       ["psp", (node["id"] if node["object"] == "payment_intent" || payload["type"].to_s.start_with?("payment_intent.") || node["id"].to_s.start_with?("pi_"))]]
    when "alipay" then [["trade", node["out_trade_no"]], ["psp", node["trade_no"]]]
    when "wechat_pay" then [["trade", node["out_trade_no"]], ["psp", node["transaction_id"]]]
    when "paypal"
      capture_event = payload["event_type"] == "PAYMENT.CAPTURE.COMPLETED" || payload["resource_type"] == "capture"
      [["trade", (node["invoice_id"] unless payload["event_type"] == "PAYMENT.CAPTURE.REFUNDED")],
       ["trade", unit["invoice_id"]], ["psp", capture["id"]], ["psp", related["capture_id"]], ["psp", (node["id"] if capture_event)]]
    else []
    end
    pairs.select { |_, value| identifier(value) }
  rescue TypeError, NoMethodError
    []
  end

  def event_object(provider, payload)
    case provider
    when "stripe" then object(object(payload["data"]).to_h["object"]) || payload
    when "wechat_pay", "paypal" then object(payload["resource"]) || payload
    else payload
    end
  end

  def first_unit(node)
    units = node["purchase_units"]
    units.is_a?(Array) ? object(units.first).to_h : {}
  end

  def object(value)
    value = JSON.parse(value) if value.is_a?(String)
    value if value.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def identifier(value)
    value.is_a?(String) && !value.empty?
  end

  def problem(kind, id, reason)
    @unresolved << { "kind" => kind, "id" => id, "reason" => reason }
  end

  def record_identity(row)
    if row.is_a?(PaymentRow)
      [row.provider, row.customer_id, row.out_trade_no, row.psp_transaction_id, object(row.raw_notify)]
    else
      [row.provider, row.customer_id, row.signing_merchant_id, row.psp_event_id]
    end
  end

  def add_plan(row, column, original, replacement, account)
    @plans << { model: row.class, id: row.id, column: column, original: original, replacement: replacement,
                record_identity: record_identity(row),
                account_id: account.id, account_identity: [account.provider, account.merchant_id, account.customer_id] }
  end
end
