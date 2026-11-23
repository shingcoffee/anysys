# frozen_string_literal: true

require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::StartOneTimePayment do
  include BillingPartitionBHelpers
  before { allow_test_root_transaction }

  def offer_providers(*keys)
    allow(Billing::OneTimeProviders).to receive(:call) do |currency:|
      keys.map do |key|
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          supported_currencies: currency.to_s.upcase == "CNY" ? %w[CNY] : %w[USD CNY] }
      end
    end
  end

  def enable_provider(aggregate, provider)
    platform = aggregate.fetch(:platform)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    Payments::MerchantAccount.unscoped_by_tenant.find_by(customer_id: platform.id, provider: provider, mode: "sandbox") ||
      create(:payment_merchant_account, provider.to_sym, customer: platform)
  end

  def stub_charge(payload:, psp_id: "pi_one_time")
    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: payload, psp_transaction_id: psp_id)
  end

  def start_payment(aggregate, provider: "stripe", **kwargs)
    described_class.call(invoice: aggregate.fetch(:invoice), provider: provider, **kwargs)
  end

  def capture_event(payment)
    { "type" => "payment_intent.succeeded", "created" => Time.current.to_i,
      "data" => { "object" => { "id" => payment.psp_transaction_id.presence || "pi_#{payment.id}",
        "currency" => payment.payment_order.currency.downcase,
        "amount_received" => Payments::Money.new(payment.amount, payment.payment_order.currency).smallest_unit,
        "metadata" => { "out_trade_no" => payment.out_trade_no } } } }
  end

  it "starts a Stripe card one-time payment and returns a secret-redacted action" do
    aggregate = billing_aggregate
    offer_providers("stripe")
    stub_charge(payload: { "client_secret" => "secret_live" }, psp_id: "pi_card")

    result = start_payment(aggregate)

    expect(result.status).to eq(:action_required)
    expect(result.action).to include(kind: :stripe_card, flow: :card, provider: "stripe",
      publishable_key: "pk_test_x", client_secret: "secret_live")
    attempt = aggregate.fetch(:invoice).collection_attempts.sole
    expect(attempt).to be_one_time
    expect(attempt.state).to eq("pending")
    expect(attempt.payment.provider).to eq("stripe")
    expect(attempt.payment.flow).to eq("card")
    expect(attempt.payment.attempt_context["operation"]).to eq("charge")
    expect(attempt.payment.attempt_context["billing_one_time"]).to eq(true)
    expect(aggregate.fetch(:method).reload).to be_active
  end

  it "starts a PayPal card one-time payment" do
    aggregate = billing_aggregate
    enable_provider(aggregate, "paypal")
    offer_providers("paypal")
    stub_charge(payload: { "paypal_order_id" => "ORDER-1" }, psp_id: "paypal_1")

    result = start_payment(aggregate, provider: "paypal")

    expect(result.status).to eq(:action_required)
    expect(result.action).to include(kind: :paypal_buttons, flow: :card, provider: "paypal",
      paypal_order_id: "ORDER-1", client_id: "client", currency: "USD")
    expect(aggregate.fetch(:invoice).collection_attempts.sole.payment.provider).to eq("paypal")
  end

  it "starts a WeChat QR one-time payment" do
    aggregate = billing_aggregate(currency: "CNY")
    enable_provider(aggregate, "wechat_pay")
    offer_providers("wechat_pay")
    stub_charge(payload: { "code_url" => "weixin://wxpay/bizpayurl?pr=abc" }, psp_id: "wx_1")

    result = start_payment(aggregate, provider: "wechat_pay")

    expect(result.status).to eq(:action_required)
    expect(result.action).to include(kind: :qr, flow: :qr, provider: "wechat_pay",
      code_url: "weixin://wxpay/bizpayurl?pr=abc")
  end

  it "starts an Alipay QR one-time payment" do
    aggregate = billing_aggregate(currency: "CNY")
    enable_provider(aggregate, "alipay")
    offer_providers("alipay")
    stub_charge(payload: { "qr_code" => "https://qr.alipay.com/bax" }, psp_id: nil)

    result = start_payment(aggregate, provider: "alipay")
    expect(result.status).to eq(:action_required)
    expect(result.action).to include(kind: :qr, flow: :qr, provider: "alipay", code_url: "https://qr.alipay.com/bax")
  end

  it "starts an Alipay H5 one-time payment from a mobile user agent" do
    aggregate = billing_aggregate(currency: "CNY")
    enable_provider(aggregate, "alipay")
    offer_providers("alipay")
    stub_charge(payload: { "h5_url" => "https://openapi.alipay.com/gateway.do?wap" }, psp_id: nil)
    request = OpenStruct.new(user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile", remote_ip: "1.1.1.1")

    result = described_class.call(invoice: aggregate.fetch(:invoice), provider: "alipay", request: request)
    expect(result.status).to eq(:action_required)
    expect(result.action).to include(kind: :h5, flow: :h5, provider: "alipay", url: "https://openapi.alipay.com/gateway.do?wap")
    expect(result.record.payment.flow).to eq("h5")
  end

  it "collects a manual-mode invoice through one-time payment without a stored method" do
    aggregate = billing_aggregate(mode: "manual")
    offer_providers("stripe")
    stub_charge(payload: { "client_secret" => "secret_manual" })

    result = start_payment(aggregate)
    expect(result.status).to eq(:action_required)
    expect(aggregate.fetch(:invoice).reload.collection_state).to eq("pending")
    expect(aggregate.fetch(:invoice).collection_attempts.sole).to be_one_time
    expect(aggregate.fetch(:invoice).effective_collection_mode).to eq("manual")
  end

  it "resumes the same pending provider without a second PSP charge" do
    aggregate = billing_aggregate
    offer_providers("stripe")
    stub_charge(payload: { "client_secret" => "secret_resume" })

    first = start_payment(aggregate)
    second = start_payment(aggregate)

    expect(second.status).to eq(:action_required)
    expect(second.record.id).to eq(first.record.id)
    expect(second.action[:client_secret]).to eq("secret_resume")
    expect(Payments::Gateway).to have_received(:charge).once
    expect(aggregate.fetch(:invoice).collection_attempts.count).to eq(1)
  end

  it "closes a pending one-time attempt when switching providers without a dunning penalty" do
    aggregate = billing_aggregate
    enable_provider(aggregate, "paypal")
    offer_providers("stripe", "paypal")
    stub_charge(payload: { "client_secret" => "secret_old" })
    start_payment(aggregate, provider: "stripe")
    allow(Payments::Activities::Query).to receive(:call)
    allow(Payments::Gateway).to receive(:close)
    stub_charge(payload: { "paypal_order_id" => "ORDER-2" }, psp_id: "paypal_2")

    result = start_payment(aggregate, provider: "paypal")

    invoice = aggregate.fetch(:invoice).reload
    expect(result.status).to eq(:action_required)
    expect(result.record.payment.provider).to eq("paypal")
    expect(invoice.collection_attempts.order(:ordinal).first).to have_attributes(state: "failed", failure_code: "provider_switched")
    expect(invoice.attempt_count).to eq(0)
    expect(invoice.collection_state).to eq("pending")
    expect(Billing::Notice.where(kind: "payment_failed", billing_invoice_id: invoice.id)).to be_empty
    expect(Payments::Gateway).to have_received(:close).once
  end

  it "settles an already-captured one-time payment instead of switching providers" do
    aggregate = billing_aggregate
    offer_providers("stripe", "paypal")
    enable_provider(aggregate, "paypal")
    stub_charge(payload: { "client_secret" => "secret_cap" }, psp_id: "pi_captured")
    start_payment(aggregate, provider: "stripe")
    payment = aggregate.fetch(:invoice).collection_attempts.sole.payment
    allow(Payments::Activities::Query).to receive(:call) do |**|
      payment.reload.mark_succeeded!(psp_id: "pi_captured", at: Time.current, notify: {})
      { status: :succeeded }
    end

    result = start_payment(aggregate, provider: "paypal")

    expect(result.status).to eq(:succeeded)
    expect(aggregate.fetch(:invoice).reload).to be_paid
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(Payments::Gateway).to have_received(:charge).once
    expect(aggregate.fetch(:invoice).collection_attempts.where(state: "pending")).to be_empty
  end

  it "refuses to start one-time payment while an off-session collection is inflight" do
    aggregate = billing_aggregate
    offer_providers("stripe")
    billing_payment(aggregate, state: "pending")
    expect(Payments::Gateway).not_to receive(:charge)

    result = start_payment(aggregate)
    expect(result.status).to eq(:conflict)
    expect(result.reason).to eq(:collection_in_flight)
  end

  it "restores invoice state after a definitive charge rejection without incrementing dunning" do
    aggregate = billing_aggregate
    offer_providers("stripe")
    allow(Payments::Gateway).to receive(:charge).and_raise(
      Payments::Errors::ApiError.new("card declined", code: "card_declined",
        payload: { "error" => { "decline_code" => "generic_decline" } }, definitive: true))

    result = start_payment(aggregate)
    invoice = aggregate.fetch(:invoice).reload
    expect(result.status).to eq(:invalid)
    expect(result.reason).to eq(:one_time_charge_failed)
    expect(invoice.attempt_count).to eq(0)
    expect(invoice.first_failed_at).to be_nil
    expect(invoice.next_attempt_at).to be_nil
    expect(invoice.collection_state).to eq("ready")
    expect(invoice).to be_open
    expect(Billing::Notice.where(kind: "payment_failed", billing_invoice_id: invoice.id)).to be_empty
    expect(invoice.collection_attempts.sole.state).to eq("failed")
  end

  it "settles via webhook and confirmation without touching the stored recurring method" do
    aggregate = billing_aggregate
    offer_providers("stripe")
    stub_charge(payload: { "client_secret" => "secret_wh" }, psp_id: "pi_webhook")
    started = start_payment(aggregate)
    payment = started.record.payment
    method = aggregate.fetch(:method)

    Payments::Activities::HandleWebhook.call(provider: "stripe", signing_account_id: aggregate.fetch(:account).id,
      signing_merchant_id: aggregate.fetch(:account).merchant_id, verified_payload: capture_event(payment))
    confirmed = Billing::Activities::ConfirmOneTimePayment.call(invoice: aggregate.fetch(:invoice).reload,
      out_trade_no: payment.out_trade_no)

    invoice = aggregate.fetch(:invoice).reload
    expect(confirmed.status).to eq(:succeeded)
    expect(invoice).to be_paid
    expect(invoice.payment_id).to eq(payment.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(method.reload).to be_active
    expect(method.is_default).to be(true)
    expect(method.payments_subscription.reload.status).to eq("active")
    expect(method.payments_subscription.next_charge_at).to be_nil

    renewal = Billing::Activities::GenerateInvoice.call(
      subscription: aggregate.fetch(:subscription).reload, purpose: "renewal",
      idempotency_key: "renewal:#{aggregate.fetch(:subscription).id}",
      period_start: aggregate.fetch(:subscription).current_period_end,
      period_end: aggregate.fetch(:subscription).current_period_end + 1.month,
      terms_snapshot: invoice.terms_snapshot
    )
    Billing::Activities::FinalizeInvoice.call(invoice: renewal)
    allow(Payments::Gateway).to receive(:charge_subscription).and_return(
      status: :requires_action, psp_transaction_id: "pi_cycle", client_secret: "secret_cycle"
    )
    collected = Billing::Activities::CollectInvoice.call(invoice: renewal)
    expect(collected.status).to eq(:requires_action)
    expect(renewal.collection_attempts.sole.payment_method).to eq(method)
    expect(method.reload).to be_active
    expect(method.is_default).to be(true)
  end

  it "treats Alipay H5 TRADE_NOT_EXIST on close as a safe local close" do
    aggregate = billing_aggregate(currency: "CNY")
    enable_provider(aggregate, "alipay")
    enable_provider(aggregate, "wechat_pay")
    offer_providers("alipay", "wechat_pay")
    request = OpenStruct.new(user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile", remote_ip: "1.1.1.1")
    stub_charge(payload: { "h5_url" => "https://openapi.alipay.com/gateway.do?wap" })
    described_class.call(invoice: aggregate.fetch(:invoice), provider: "alipay", request: request)
    allow(Payments::Activities::Query).to receive(:call)
    allow(Payments::Gateway).to receive(:close).and_raise(
      Payments::Errors::ApiError.new("trade not exist", code: "40004",
        payload: { "sub_code" => "ACQ.TRADE_NOT_EXIST" }, definitive: true))
    stub_charge(payload: { "code_url" => "weixin://wxpay/bizpayurl?pr=switch" }, psp_id: "wx_2")

    result = described_class.call(invoice: aggregate.fetch(:invoice).reload, provider: "wechat_pay")
    expect(result.status).to eq(:action_required)
    expect(result.record.payment.provider).to eq("wechat_pay")
    expect(aggregate.fetch(:invoice).collection_attempts.order(:ordinal).first.failure_code).to eq("provider_switched")
  end
end
