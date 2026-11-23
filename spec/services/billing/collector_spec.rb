# frozen_string_literal: true
require "rails_helper"
require_relative "partition_b_helpers"

RSpec.describe Billing::Collector do
  include BillingPartitionBHelpers
  before { allow_test_root_transaction }

  it "reconciles a verified Payments success whose billing projection was lost" do
    aggregate = billing_aggregate
    payment = billing_payment(aggregate)
    result = described_class.collect(aggregate.fetch(:invoice), trigger: :reconcile)
    expect(result.status).to eq(:succeeded)
    expect(aggregate.fetch(:invoice).reload.payment_id).to eq(payment.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
  end

  it "keeps a query API error ambiguous instead of minting a replacement charge" do
    aggregate = billing_aggregate
    billing_payment(aggregate, state: "unknown")
    allow(Billing::Providers).to receive(:query).and_raise(Payments::Errors::ApiError.new("unavailable", code: 500))
    expect { described_class.collect(aggregate.fetch(:invoice), trigger: :reconcile) }.not_to change(Payments::Payment, :count)
    expect(aggregate.fetch(:invoice).collection_attempts.sole.reload.state).to eq("unknown")
    expect(aggregate.fetch(:invoice).reload.attempt_count).to eq(0)
  end

  it "does not start a prepared payment after local removal or request expiry" do
    aggregate = billing_aggregate
    billing_payment(aggregate, state: "prepared")
    Billing::Activities::RemovePaymentMethod.call(payment_method: aggregate.fetch(:method))
    expect(Payments::Gateway).not_to receive(:charge_subscription)
    result = described_class.collect(aggregate.fetch(:invoice), trigger: :reconcile)
    expect(result.status).to eq(:blocked)
    expect(aggregate.fetch(:invoice).collection_attempts.sole.reload.state).to eq("failed")
    expect(aggregate.fetch(:invoice).reload.attempt_count).to eq(0)
  end

  it "queries a second unresolved payment even after an older late capture settled the invoice" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    first = billing_payment(aggregate)
    Billing::Activities::MarkInvoicePaid.call(invoice: invoice, payment: first, source: :gateway)
    second = billing_payment(aggregate, ordinal: 2, state: "unknown")
    allow(Billing::Providers).to receive(:query).and_return(status: :succeeded, psp_transaction_id: "pi_second", amount: BigDecimal("100"), currency: "USD", settled_at: Time.current)
    described_class.collect(invoice, trigger: :reconcile)
    expect(second.reload.status).to eq("succeeded")
    expect(invoice.reload.payment_id).to eq(first.id)
    expect(invoice.settlement_review_code).to eq("duplicate_capture")
  end
end
