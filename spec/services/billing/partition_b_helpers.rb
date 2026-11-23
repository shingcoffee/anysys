# frozen_string_literal: true

module BillingPartitionBHelpers
  def billing_aggregate(mode: "gateway", purpose: "initial", grace: 14, currency: "USD", finalize: true)
    allow(Billing::Onboarding).to receive(:call)
    tenant = create(:customer, locale: "en")
    platform = ensure_platform_customer
    Payments::PlatformGateway.for_provider("stripe").update!(available: true)
    account = Payments::MerchantAccount.unscoped_by_tenant.find_by(customer_id: platform.id, provider: "stripe", mode: "sandbox") || create(:payment_merchant_account, :stripe, customer: platform)
    actor = create(:user, :admin, customer: tenant)
    plan = create(:billing_plan, amount_usd: 100, amount_cny: 100)
    terms = Billing::PlanChangePolicy.snapshot(plan: plan, currency: currency)
    start = Time.current.change(usec: 0)
    subscription = create(:billing_subscription, customer: tenant, plan: plan, currency: currency,
      status: purpose == "initial" ? "pending" : "active", amount_cents: 10_000, plan_snapshot: terms,
      current_period_start: start, current_period_end: start + 1.month)
    method = create(:billing_payment_method, customer: tenant, provider: "stripe", merchant_account: account,
      authorized_by_id: actor.id, requested_default: true, status: "active", is_default: true)
    token = Payments::PaymentMethod.create!(customer_id: platform.id, user_id: nil, provider: "stripe",
      billing_customer_id: tenant.id, billing_authorized_by_id: actor.id, status: "active",
      psp_customer_id: "cus_billing_#{method.id}", psp_payment_method_id: "pm_billing_#{method.id}", brand: "visa", last4: "4242")
    mandate = create(:payment_subscription, customer: platform, provider: "stripe", payment_method: token,
      managed_by: "billing", metadata: { "billing_owned" => true }, next_charge_at: nil,
      external_ref: "billing-pm-#{tenant.id}-stripe-#{method.id}", currency: currency.downcase)
    method.update!(payments_subscription: mandate, authorization_reference: "seti_#{method.id}")
    policy = terms.merge("tax_rate_bps" => 0, "collection_mode" => mode, "grace_period_days" => grace, "dunning_schedule" => [1, 3, 7], "due_at" => start.iso8601(6),
      "billing_anchor_day" => start.day, "billing_anchor_month" => start.month)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: purpose,
      idempotency_key: "initial:#{subscription.id}", period_start: start, period_end: start + 1.month, terms_snapshot: policy,
      extra_line_items: purpose == "proration" ? [{ description: "Proration", kind: "proration", quantity: 1, unit_amount_cents: 10_000, amount_cents: 10_000 }] : [])
    Billing::Activities::FinalizeInvoice.call(invoice: invoice) if finalize
    allow(Billing::AvailableProviders).to receive(:call).and_return([{ key: "stripe", setup_kind: :stripe_setup }])
    { tenant: tenant, platform: platform, account: account, actor: actor, plan: plan, terms: terms,
      subscription: subscription, method: method, mandate: mandate, token: token, invoice: invoice }
  end

  def allow_test_root_transaction
    # RSpec holds one rollback transaction. Allow that harness boundary, but
    # still refuse nested domain transactions and assert HTTP sees only root.
    connection = Billing::Invoice.connection
    allow(connection).to receive(:transaction_open?).and_wrap_original { |original| original.call && connection.open_transactions > 1 }
  end

  def setup_evidence(aggregate, status: "succeeded")
    method = aggregate.fetch(:method)
    account = aggregate.fetch(:account)
    { "id" => method.authorization_reference, "status" => status,
      "customer" => aggregate.fetch(:token).psp_customer_id,
      "metadata" => { "merchant_id" => account.merchant_id, "merchant_account_id" => account.id.to_s,
        "billing_payment_method_id" => method.id.to_s, "billing_customer_id" => method.customer_id.to_s },
      "payment_method" => { "id" => aggregate.fetch(:token).psp_payment_method_id, "type" => "card",
        "customer" => aggregate.fetch(:token).psp_customer_id, "card" => { "brand" => "visa", "last4" => "4242", "exp_month" => 12, "exp_year" => 2099 } } }
  end

  def billing_payment(aggregate, ordinal: 1, state: "succeeded", paid_at: Time.current)
    invoice = aggregate.fetch(:invoice)
    order = Payments::Order.unscoped_by_tenant.find_or_create_by!(customer_id: aggregate.fetch(:platform).id,
      external_ref: "billing-inv-#{invoice.id}") { |row| row.amount = BigDecimal(invoice.total_cents.to_s) / 100; row.currency = invoice.currency; row.subject = invoice.terms_snapshot.fetch("name") }
    payment = create(:payment, customer: aggregate.fetch(:platform), payment_order: order, provider: "stripe", flow: "card",
      out_trade_no: "billing-invoice-#{invoice.id}-#{ordinal}", amount: order.amount)
    Payments::Activities::PrepareAttempt.call(customer: aggregate.fetch(:platform), order: order, payment: payment, operation: "billing_collection")
    invoice.collection_attempts.create!(customer_id: invoice.customer_id, ordinal: ordinal, request_key: payment.out_trade_no,
      payment: payment, payment_method: aggregate.fetch(:method), merchant_account: aggregate.fetch(:account), state: state)
    payment.mark_succeeded!(psp_id: "pi_#{payment.id}", at: paid_at, notify: {}) if state == "succeeded"
    payment
  end
end
