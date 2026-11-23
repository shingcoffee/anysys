# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::SetUpPaymentMethod do
  include BillingPartitionBHelpers
  before { allow_test_root_transaction }

  it "uses the official Stripe SDK with stable keys and persists only a pending platform token" do
    aggregate = billing_aggregate
    key = SecureRandom.uuid
    customer_request = stub_request(:post, "https://api.stripe.com/v1/customers")
      .with { |request| request.headers.fetch("Idempotency-Key").match?(/\Abilling-method-\d+-customer\z/) }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "cus_new" }.to_json)
    setup_request = stub_request(:post, "https://api.stripe.com/v1/setup_intents")
      .with { |request| request.headers.fetch("Idempotency-Key").match?(/\Abilling-method-\d+-setup\z/) }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "seti_new", client_secret: "seti_secret" }.to_json)
    result = described_class.call(customer: aggregate.fetch(:tenant), actor: aggregate.fetch(:actor), provider: "stripe",
      request_key: key, return_url: "https://example.test/#{aggregate.fetch(:tenant).id}/admin/settings/billing/payment_methods")
    method = result.payment_method
    expect(result.status).to eq(:authorization_required)
    expect(result.action).to include(kind: :stripe_setup, client_secret: "seti_secret")
    expect(method.authorization_reference).to eq("seti_new")
    token = method.payments_subscription.payment_method
    expect(token.customer_id).to eq(81_721_200)
    expect(token.user_id).to be_nil
    expect(token.billing_customer_id).to eq(method.customer_id)
    expect(token.chargeable?).to be(false)
    expect(aggregate.fetch(:method).reload.is_default).to be(true)
    expect(method.attributes.values).not_to include("seti_secret")
    expect(customer_request).to have_been_requested.once
    expect(setup_request).to have_been_requested.once
  end

  it "returns pending after lost Stripe setup response without discarding correlation" do
    aggregate = billing_aggregate
    allow(Payments::Gateway).to receive(:billing_vault_card).and_raise(Payments::Errors::TransportError, "lost")
    key = SecureRandom.uuid
    2.times do
      result = described_class.call(customer: aggregate.fetch(:tenant), actor: aggregate.fetch(:actor), provider: "stripe", request_key: key,
        return_url: "https://example.test/#{aggregate.fetch(:tenant).id}/admin/settings/billing/payment_methods")
      expect(result.status).to eq(:pending)
    end
    expect(Billing::PaymentMethod.where(customer_id: aggregate.fetch(:tenant).id, request_key: key).count).to eq(1)
  end

  it "rejects a cross-tenant authorizer before preparing any PSP resource" do
    aggregate = billing_aggregate
    stranger = create(:user, :admin)
    expect(Payments::Gateway).not_to receive(:billing_vault_card)
    result = described_class.call(customer: aggregate.fetch(:tenant), actor: stranger, provider: "stripe", request_key: SecureRandom.uuid,
      return_url: "https://example.test/#{aggregate.fetch(:tenant).id}/admin/settings/billing/payment_methods")
    expect(result.reason).to eq(:admin_required)
  end
end
