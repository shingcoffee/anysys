# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::OneTimePaymentAction do
  before { allow(Billing::Onboarding).to receive(:call) }
  after { Current.reset }

  let(:platform) { ensure_platform_customer }
  let(:tenant) { create(:customer) }
  let(:subscription) { create(:billing_subscription, customer: tenant, currency: "USD") }
  let(:invoice) do
    create(:billing_invoice, :open, customer: tenant, subscription: subscription,
           currency: "USD", subtotal_cents: 2900, total_cents: 2900)
  end

  def create_one_time_attempt(provider:, flow:, account:, prepay_payload:, payment_status: "pending", attempt_customer: tenant)
    order = create(:payment_order, customer: platform, external_ref: "billing-inv-#{invoice.id}",
                   amount: 29.00, currency: invoice.currency, subject: "Pro")
    key = Payments::OutTradeNo.generate(prefix: "bi", customer_id: tenant.id)
    payload_with_context = prepay_payload.merge(
      Payments::Payment::ATTEMPT_CONTEXT_KEY => {
        "operation" => "charge",
        "merchant_account_id" => account.id,
        "merchant_id" => account.merchant_id,
        "mode" => account.mode
      }
    )
    payment = create(:payment, customer: platform, payment_order: order, provider: provider,
                     flow: flow, out_trade_no: key, amount: 29.00, status: payment_status,
                     prepay_payload: payload_with_context)
    invoice.collection_attempts.create!(
      customer_id: attempt_customer.id,
      ordinal: 1,
      request_key: key,
      payment: payment,
      billing_payment_method_id: nil,
      merchant_account_id: account.id,
      state: "pending"
    )
  end

  it "exposes only publishable_key and client_secret for Stripe card checkout" do
    account = create(:payment_merchant_account, :stripe, customer: platform,
                     credentials: { publishable_key: "pk_test_safe", secret_key: "sk_test_never", webhook_signing_secret: "whsec_never" })
    attempt = create_one_time_attempt(provider: "stripe", flow: "card", account: account,
                                      prepay_payload: { "client_secret" => "pi_secret_123" })

    action = described_class.for(invoice: invoice)

    expect(action).to eq(
      kind: :stripe_card,
      flow: :card,
      provider: "stripe",
      out_trade_no: attempt.payment.out_trade_no,
      publishable_key: "pk_test_safe",
      client_secret: "pi_secret_123"
    )
    expect(action.values.join(" ")).not_to include("sk_test_never", "whsec_never")
  end

  it "exposes only client_id and paypal_order_id for PayPal Smart Buttons" do
    account = create(:payment_merchant_account, :paypal, customer: platform,
                     credentials: { client_id: "paypal_cid_safe", client_secret: "paypal_sec_never", webhook_id: "wh_never" })
    attempt = create_one_time_attempt(provider: "paypal", flow: "card", account: account,
                                      prepay_payload: { "paypal_order_id" => "ORDER-999" })

    action = described_class.for(invoice: invoice)

    expect(action).to eq(
      kind: :paypal_buttons,
      flow: :card,
      provider: "paypal",
      out_trade_no: attempt.payment.out_trade_no,
      client_id: "paypal_cid_safe",
      paypal_order_id: "ORDER-999",
      currency: "USD"
    )
    expect(action.values.join(" ")).not_to include("paypal_sec_never", "wh_never")
  end

  it "rejects javascript:, http:, and malformed H5 URLs while allowing https:" do
    subscription.update!(currency: "CNY")
    invoice.update_columns(currency: "CNY")
    account = create(:payment_merchant_account, :alipay, customer: platform)

    attempt = create_one_time_attempt(provider: "alipay", flow: "h5", account: account,
                                      prepay_payload: { "h5_url" => "javascript:alert(1)" })
    expect(described_class.for(invoice: invoice)).to be_nil

    attempt.payment.update!(prepay_payload: attempt.payment.prepay_payload.merge("h5_url" => "http://m.alipay.com/pay"))
    expect(described_class.for(invoice: invoice)).to be_nil

    attempt.payment.update!(prepay_payload: attempt.payment.prepay_payload.merge("h5_url" => "not a uri ://"))
    expect(described_class.for(invoice: invoice)).to be_nil

    attempt.payment.update!(prepay_payload: attempt.payment.prepay_payload.merge("h5_url" => "https://openapi.alipay.com/gateway.do?sign=abc"))
    expect(described_class.for(invoice: invoice)).to include(
      kind: :h5,
      flow: :h5,
      provider: "alipay",
      url: "https://openapi.alipay.com/gateway.do?sign=abc"
    )
  end

  it "strips internal _attempt metadata from JSAPI payloads" do
    subscription.update!(currency: "CNY")
    invoice.update_columns(currency: "CNY")
    account = create(:payment_merchant_account, :wechat_pay, customer: platform)
    create_one_time_attempt(provider: "wechat_pay", flow: "jsapi", account: account,
                            prepay_payload: { "prepay_id" => "wx123", "paySign" => "sig" })

    action = described_class.for(invoice: invoice)

    expect(action[:kind]).to eq(:jsapi)
    expect(action[:jsapi_params]).to eq("prepay_id" => "wx123", "paySign" => "sig")
    expect(action[:jsapi_params]).not_to have_key(Payments::Payment::ATTEMPT_CONTEXT_KEY)
  end

  it "returns nil for paid, void, or tenant-mismatched attempts" do
    account = create(:payment_merchant_account, :stripe, customer: platform)
    other_tenant = create(:customer)
    create_one_time_attempt(provider: "stripe", flow: "card", account: account,
                            prepay_payload: { "client_secret" => "pi_secret" }, attempt_customer: other_tenant)
    expect(described_class.for(invoice: invoice)).to be_nil
  end
end
