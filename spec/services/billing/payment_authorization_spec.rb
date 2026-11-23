# frozen_string_literal: true
require "rails_helper"
require_relative "partition_b_helpers"

RSpec.describe Billing::PaymentAuthorization do
  include BillingPartitionBHelpers

  it "activates only the provider-confirmed customer-bound token and never schedules general recurring charges" do
    aggregate = billing_aggregate
    method = aggregate.fetch(:method)
    method.update!(status: "pending", is_default: false)
    aggregate.fetch(:mandate).update!(status: "pending_sign")
    payload = setup_evidence(aggregate)
    allow(Payments::Gateway).to receive(:billing_setup_intent).and_return(payload)
    expect(described_class.confirm!(payment_method: method).status).to eq(:active)
    expect(method.reload.is_default).to be(true)
    expect(aggregate.fetch(:mandate).reload.next_charge_at).to be_nil
    expect(aggregate.fetch(:mandate).billing_owned?).to be(true)
  end

  it "rejects a browser hash or a provider event for another merchant" do
    aggregate = billing_aggregate
    method = aggregate.fetch(:method)
    expect { described_class.confirm!(payment_method: method, verified_event: setup_evidence(aggregate)) }.to raise_error(Payments::Errors::TenantMismatch)
    account = create(:payment_merchant_account, :stripe, customer: create(:customer))
    event = described_class.verified_event(account: account, payload: setup_evidence(aggregate))
    expect { described_class.confirm!(payment_method: method, verified_event: event) }.to raise_error(Payments::Errors::TenantMismatch)
  end

  it "rejects a genuine Stripe token attached to a different PSP customer" do
    aggregate = billing_aggregate
    payload = setup_evidence(aggregate)
    payload["payment_method"]["customer"] = "cus_other"
    allow(Payments::Gateway).to receive(:billing_setup_intent).and_return(payload)
    expect { described_class.confirm!(payment_method: aggregate.fetch(:method)) }.to raise_error(Payments::Errors::TenantMismatch)
  end

  it "does not resurrect a removed method on a late verified setup" do
    aggregate = billing_aggregate
    method = aggregate.fetch(:method)
    Billing::Activities::RemovePaymentMethod.call(payment_method: method)
    allow(Payments::Gateway).to receive(:billing_setup_intent).and_return(setup_evidence(aggregate))
    expect(described_class.confirm!(payment_method: method).reason).to eq(:method_removed)
    expect(method.reload.status).to eq("removed")
    expect(method.revocation_state).to eq("pending")
    expect(aggregate.fetch(:mandate).reload.status).to eq("cancelled")
    expect(aggregate.fetch(:token).reload.status).to eq("removed")
  end

  it "routes an exact signed Alipay agreement before trade processing" do
    aggregate = billing_aggregate
    account = create(:payment_merchant_account, :alipay, customer: aggregate.fetch(:platform))
    method = create(:billing_payment_method, customer: aggregate.fetch(:tenant), provider: "alipay", merchant_account: account, authorized_by_id: aggregate.fetch(:actor).id)
    mandate = create(:payment_subscription, customer: aggregate.fetch(:platform), provider: "alipay", currency: "cny", status: "pending_sign", managed_by: "billing", external_ref: "billing-pm-#{method.customer_id}-alipay-#{method.id}")
    method.update!(payments_subscription: mandate, authorization_reference: mandate.external_ref)
    result = described_class.handle_verified_event!(account: account, payload: { "external_agreement_no" => mandate.external_ref, "agreement_no" => "agr_1", "status" => "NORMAL" })
    expect(result.status).to eq(:active)
    expect(mandate.reload.psp_agreement_id).to eq("agr_1")
    expect(mandate.next_charge_at).to be_nil
  end

  it "retrieves an existing Stripe action on GET without mutating authorization or replaying setup" do
    aggregate = billing_aggregate
    method = aggregate.fetch(:method)
    method.update!(status: "pending", is_default: false)
    payload = setup_evidence(aggregate, status: "requires_payment_method").merge("client_secret" => "seti_existing_secret")
    allow(Payments::Gateway).to receive(:billing_setup_intent).and_return(payload)
    expect(Payments::Gateway).not_to receive(:billing_vault_card)
    before = [method.attributes, aggregate.fetch(:mandate).attributes, aggregate.fetch(:token).attributes]
    action = described_class.action_for(payment_method: method, return_url: "https://example.test/#{method.customer_id}/admin/settings/billing/payment_methods/#{method.id}/authorization")
    expect(action).to include(kind: :stripe_setup, client_secret: "seti_existing_secret")
    expect([method.reload.attributes, aggregate.fetch(:mandate).reload.attributes, aggregate.fetch(:token).reload.attributes]).to eq(before)
  end

  it "does not activate a succeeded setup as a side effect of the authorization GET" do
    aggregate = billing_aggregate
    method = aggregate.fetch(:method)
    method.update!(status: "pending", is_default: false)
    allow(Payments::Gateway).to receive(:billing_setup_intent).and_return(setup_evidence(aggregate))
    expect(described_class.action_for(payment_method: method, return_url: "https://example.test")).to be_nil
    expect(method.reload.status).to eq("pending")
  end

  it "does not demote a compatible default when a different-currency pending setup completes" do
    aggregate = billing_aggregate
    original = aggregate.fetch(:method)
    replacement = create(:billing_payment_method, customer: original.customer, provider: "stripe", merchant_account: aggregate.fetch(:account),
      authorized_by_id: aggregate.fetch(:actor).id, requested_default: true)
    mandate = create(:payment_subscription, customer: aggregate.fetch(:platform), provider: "stripe", currency: "cny", managed_by: "billing", status: "pending_sign",
      next_charge_at: nil, external_ref: "billing-pm-#{replacement.customer_id}-stripe-#{replacement.id}")
    replacement.update!(payments_subscription: mandate, authorization_reference: "seti_replacement")
    Billing::PaymentAuthorization.ensure_stripe_token!(replacement, "cus_replacement")
    payload = setup_evidence(aggregate.merge(method: replacement, token: mandate.reload.payment_method))
    payload["payment_method"]["id"] = "pm_replacement"
    allow(Payments::Gateway).to receive(:billing_setup_intent).and_return(payload)
    expect(described_class.confirm!(payment_method: replacement).status).to eq(:active)
    expect(replacement.reload.is_default).to be(false)
    expect(original.reload.is_default).to be(true)
    expect(Billing::Activities::MakeDefaultPaymentMethod.call(customer: original.customer, payment_method: replacement).reason).to eq(:currency_mismatch)
  end

  it "leaves trade notifications carrying an agreement reference to the trade dispatcher" do
    aggregate = billing_aggregate
    account = create(:payment_merchant_account, :alipay, customer: aggregate.fetch(:platform))
    payload = { "agreement_no" => "agreement_trade", "trade_status" => "TRADE_SUCCESS", "notify_type" => "trade_status_sync", "out_trade_no" => "billing-invoice-1-1" }
    expect(described_class.handle_verified_event!(account: account, payload: payload)).to be_nil
  end
end
