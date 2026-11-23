# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::RemovePaymentMethod do
  include BillingPartitionBHelpers

  it "stops the local mandate and token before any provider cleanup is dispatched" do
    aggregate = billing_aggregate
    expect(Payments::Gateway).not_to receive(:cancel_subscription)
    expect(Payments::Gateway).not_to receive(:detach_token)
    result = described_class.call(payment_method: aggregate.fetch(:method))
    expect(result.status).to eq(:removed)
    expect(aggregate.fetch(:method).reload.revocation_state).to eq("pending")
    expect(aggregate.fetch(:method).is_default).to be(false)
    expect(aggregate.fetch(:mandate).reload.status).to eq("cancelled")
    expect(aggregate.fetch(:mandate).next_charge_at).to be_nil
    expect(aggregate.fetch(:token).reload.chargeable?).to be(false)
  end

  it "also permits removing an unfinished authorization" do
    aggregate = billing_aggregate
    aggregate.fetch(:method).update!(status: "pending", is_default: false)
    expect(described_class.call(payment_method: aggregate.fetch(:method)).status).to eq(:removed)
    expect(described_class.call(payment_method: aggregate.fetch(:method)).status).to eq(:unchanged)
  end

  it "retains retryable cleanup state when the provider is unreachable" do
    aggregate = billing_aggregate
    described_class.call(payment_method: aggregate.fetch(:method))
    adapter = instance_double(Billing::Providers::Stripe)
    allow(Billing::Providers).to receive(:for).and_return(adapter)
    allow(adapter).to receive(:revoke).and_raise(Payments::Errors::TransportError, "timeout")
    Billing::Cron::RevokePaymentMethods.perform
    method = aggregate.fetch(:method).reload
    expect(method.status).to eq("removed")
    expect(method.revocation_state).to eq("failed")
    expect(method.revocation_attempt_count).to eq(1)
    expect(method.revocation_next_attempt_at).to be > Time.current
  end
end
