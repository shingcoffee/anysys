# frozen_string_literal: true
require "rails_helper"
require_relative "../../services/billing/partition_b_helpers"

RSpec.describe Billing::CollectionAttempt, type: :model do
  include BillingPartitionBHelpers

  it "prevents two durable inflight attempts for one invoice" do
    aggregate = billing_aggregate
    billing_payment(aggregate, state: "unknown")
    expect { billing_payment(aggregate, ordinal: 2, state: "prepared") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(aggregate.fetch(:invoice).collection_attempts.inflight.count).to eq(1)
  end

  it "allows a one-time attempt without a stored payment method" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    attempt = invoice.collection_attempts.create!(customer_id: invoice.customer_id, ordinal: 1,
      request_key: "bi-one-time-#{invoice.id}", merchant_account: aggregate.fetch(:account),
      billing_payment_method_id: nil, state: "prepared")

    expect(attempt).to be_one_time
    expect(attempt.payment_method).to be_nil
    billing_payment(aggregate, ordinal: 2, state: "failed")
    expect(invoice.collection_attempts.find_by!(ordinal: 2)).not_to be_one_time
  end
end
