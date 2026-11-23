# frozen_string_literal: true

require "rails_helper"
require_relative "../../billing/partition_b_helpers"

RSpec.describe Payments::Activities::HandleWebhook do
  include BillingPartitionBHelpers

  after { Current.reset }

  def dispatch_verified(account, payload)
    described_class.call(provider: account.provider, signing_account_id: account.id,
                         signing_merchant_id: account.merchant_id, verified_payload: payload)
  end

  def capture_event(payment)
    { "type" => "payment_intent.succeeded", "created" => Time.current.to_i,
      "data" => { "object" => { "id" => payment.psp_transaction_id.presence || "pi_#{payment.id}",
        "currency" => payment.payment_order.currency.downcase,
        "amount_received" => Payments::Money.new(payment.amount, payment.payment_order.currency).smallest_unit,
        "metadata" => { "out_trade_no" => payment.out_trade_no } } } }
  end

  it "projects a verified Billing SetupIntent through B using its disabled historical account" do
    aggregate = billing_aggregate
    account = aggregate.fetch(:account)
    method = aggregate.fetch(:method)
    method.update!(status: "pending", is_default: false)
    aggregate.fetch(:mandate).update!(status: "pending_sign")
    account.update!(status: "disabled")
    allow(Payments::CredentialResolver).to receive(:default_mode).and_return("production")
    evidence = setup_evidence(aggregate)
    baseline = ActiveRecord::Base.connection.open_transactions
    lookup = stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/setup_intents/#{method.authorization_reference}\?})
      .with(headers: { "Authorization" => "Bearer #{account.credential(:secret_key)}" })
      .to_return do
        expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline)
        { status: 200, body: evidence.to_json, headers: { "Content-Type" => "application/json" } }
      end

    result = dispatch_verified(account, { "type" => "setup_intent.succeeded", "data" => { "object" => evidence } })

    expect(result.status).to eq(:active)
    expect(method.reload.is_default).to be(false)
    expect(Billing::Providers.readiness_reason(payment_method: method)).to eq(:provider_unavailable)
    expect(aggregate.fetch(:mandate).reload.status).to eq("active")
    expect(aggregate.fetch(:mandate).next_charge_at).to be_nil
    expect(aggregate.fetch(:token).reload.psp_payment_method_id).to eq(evidence.dig("payment_method", "id"))
    expect(lookup).to have_been_requested.once
  end

  it "keeps B authorization lookup failures retryable rather than returning a processed pending result" do
    aggregate = billing_aggregate
    method = aggregate.fetch(:method)
    method.update!(status: "pending", is_default: false)
    aggregate.fetch(:mandate).update!(status: "pending_sign")
    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/setup_intents/#{method.authorization_reference}\?})
      .to_return(status: 503, body: { error: { message: "temporarily unavailable" } }.to_json)
    payload = { "type" => "setup_intent.succeeded", "data" => { "object" => setup_evidence(aggregate) } }

    expect { dispatch_verified(aggregate.fetch(:account), payload) }.to raise_error(Payments::Errors::TransportError)

    expect(method.reload.status).to eq("pending")
    expect(aggregate.fetch(:mandate).reload.status).to eq("pending_sign")
  end

  it "processes an exact Alipay Billing agreement before routing trade-shaped fields" do
    aggregate = billing_aggregate
    platform = aggregate.fetch(:platform)
    account = create(:payment_merchant_account, :alipay, customer: platform)
    method = create(:billing_payment_method, customer: aggregate.fetch(:tenant), provider: "alipay",
                    merchant_account: account, authorized_by_id: aggregate.fetch(:actor).id)
    mandate = create(:payment_subscription, customer: platform, provider: "alipay", currency: "cny",
                     managed_by: "billing", status: "pending_sign", next_charge_at: nil,
                     external_ref: "billing-pm-#{method.customer_id}-alipay-#{method.id}")
    method.update!(payments_subscription: mandate, authorization_reference: mandate.external_ref)
    trade = create(:payment, customer: platform, provider: "alipay", status: "pending")

    result = dispatch_verified(account, { "external_agreement_no" => mandate.external_ref,
      "agreement_no" => "agr_verified", "status" => "NORMAL",
      "out_trade_no" => trade.out_trade_no, "trade_status" => "TRADE_SUCCESS" })

    expect(result.status).to eq(:active)
    expect(method.reload.status).to eq("active")
    expect(mandate.reload.psp_agreement_id).to eq("agr_verified")
    expect(mandate.next_charge_at).to be_nil
    expect(trade.reload.status).to eq("pending")
  end

  it "settles an actual B collection attempt and applies A entitlements exactly once" do
    aggregate = billing_aggregate
    payment = billing_payment(aggregate, state: "unknown")

    dispatch_verified(aggregate.fetch(:account), capture_event(payment))
    dispatch_verified(aggregate.fetch(:account), capture_event(payment))

    invoice = aggregate.fetch(:invoice).reload
    expect(payment.reload.status).to eq("succeeded")
    expect(invoice.status).to eq("paid")
    expect(invoice.payment_id).to eq(payment.id)
    expect(invoice.settlement_source).to eq("gateway")
    expect(invoice.entitlements_applied_at).to be_present
    expect(invoice.collection_attempts.sole.state).to eq("succeeded")
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(Billing::Notice.where(kind: "payment_succeeded", billing_invoice_id: invoice.id).count).to eq(1)
  end

  it "retries a failed invoice projection on an already-captured payment without losing or recapturing money" do
    aggregate = billing_aggregate
    payment = billing_payment(aggregate, state: "unknown")
    payload = capture_event(payment)
    allow(Billing::Activities::ApplyInvoiceSettlement).to receive(:call).and_raise("projection temporarily unavailable")

    expect { dispatch_verified(aggregate.fetch(:account), payload) }.to raise_error(RuntimeError, /projection temporarily unavailable/)
    expect(payment.reload.status).to eq("succeeded")
    paid_at = payment.paid_at
    expect(aggregate.fetch(:invoice).reload.status).to eq("open")

    allow(Billing::Activities::ApplyInvoiceSettlement).to receive(:call).and_call_original
    dispatch_verified(aggregate.fetch(:account), payload)

    expect(payment.reload.paid_at).to eq(paid_at)
    expect(aggregate.fetch(:invoice).reload.payment_id).to eq(payment.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(Billing::Notice.where(kind: "payment_succeeded", billing_invoice_id: aggregate.fetch(:invoice).id).count).to eq(1)
  end

  it "repairs a missing invoice projection from a persisted capture without requiring another gateway query" do
    aggregate = billing_aggregate
    payment = billing_payment(aggregate)
    expect(Payments::Gateway).not_to receive(:query)

    result = Payments::Activities::Query.call(customer: aggregate.fetch(:platform), payment: payment)

    expect(result[:status]).to eq(:succeeded)
    expect(aggregate.fetch(:invoice).reload.payment_id).to eq(payment.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
  end

  it "does not revive a Billing mandate from a general recurring SCA reference" do
    aggregate = billing_aggregate
    mandate = aggregate.fetch(:mandate)
    mandate.update!(status: "paused")
    order = create(:payment_order, customer: aggregate.fetch(:platform), external_ref: "sub-#{mandate.id}-#{Date.current}",
                   amount: 20.00, currency: "USD")
    payment = create(:payment, customer: aggregate.fetch(:platform), payment_order: order,
                     provider: "stripe", flow: "card", status: "pending", amount: 20.00)
    Payments::Activities::PrepareAttempt.call(customer: aggregate.fetch(:platform), order: order, payment: payment, operation: "charge_token")

    dispatch_verified(aggregate.fetch(:account), capture_event(payment))

    expect(payment.reload.status).to eq("succeeded")
    expect(mandate.reload.status).to eq("paused")
    expect(mandate.next_charge_at).to be_nil
  end

  it "backfills a local member vault using the exact disabled non-current-mode verification account" do
    tenant = create(:customer)
    historical = create(:payment_merchant_account, :stripe, customer: tenant, mode: "production", status: "disabled",
                        credentials: { secret_key: "sk_live_historical" })
    create(:payment_merchant_account, :stripe, customer: tenant,
           credentials: { secret_key: "sk_test_replacement" })
    token = create(:payment_method, customer: tenant, psp_customer_id: "cus_historical",
                   psp_payment_method_id: "pending:seti_historical", brand: nil, last4: nil)
    lookup = stub_request(:get, "https://api.stripe.com/v1/payment_methods/pm_historical")
      .with(headers: { "Authorization" => "Bearer sk_live_historical" })
      .to_return(status: 200, body: { id: "pm_historical", card: { brand: "visa", last4: "4242", exp_month: 12, exp_year: 2099 } }.to_json)

    dispatch_verified(historical, { "type" => "setup_intent.succeeded", "data" => { "object" => {
      "id" => "seti_historical", "customer" => "cus_historical", "payment_method" => "pm_historical"
    } } })

    expect(token.reload.psp_payment_method_id).to eq("pm_historical")
    expect(token.last4).to eq("4242")
    expect(lookup).to have_been_requested.once
  end

  it "never substitutes an active merchant when historical card fetch has no explicit account" do
    tenant = create(:customer)
    create(:payment_merchant_account, :stripe, customer: tenant)

    expect { Payments::Gateway.fetch_payment_method(customer: tenant, provider: "stripe",
                                                    psp_pm_id: "pm_unbound", historical: true) }
      .to raise_error(Payments::Errors::CredentialsMissing)
  end

  it "does not backfill an unrelated singleton placeholder when the verified SetupIntent ID does not match" do
    tenant = create(:customer)
    account = create(:payment_merchant_account, :stripe, customer: tenant)
    token = create(:payment_method, customer: tenant, psp_customer_id: "cus_single",
                   psp_payment_method_id: "pending:seti_original")
    expect(Payments::Gateway).not_to receive(:fetch_payment_method)

    dispatch_verified(account, { "type" => "setup_intent.succeeded", "data" => { "object" => {
      "id" => "seti_other", "customer" => "cus_single", "payment_method" => "pm_unrelated"
    } } })

    expect(token.reload.psp_payment_method_id).to eq("pending:seti_original")
  end
end
