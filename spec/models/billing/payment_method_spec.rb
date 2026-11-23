# frozen_string_literal: true
require "rails_helper"
require_relative "../../services/billing/partition_b_helpers"

RSpec.describe Billing::PaymentMethod, type: :model do
  include BillingPartitionBHelpers

  it "keeps pending methods visible without making them default-ready" do
    aggregate = billing_aggregate
    pending = create(:billing_payment_method, customer: aggregate.fetch(:tenant), provider: "stripe", merchant_account: aggregate.fetch(:account), status: "pending")
    expect(described_class.where(customer_id: pending.customer_id)).to include(pending)
    expect(described_class.default_method).not_to include(pending)
    expect(Billing::Activities::MakeDefaultPaymentMethod.call(customer: pending.customer, payment_method: pending).reason).to eq(:method_inactive)
    expect(aggregate.fetch(:method).reload.is_default).to be(true)
  end

  it "requires persistent request identity" do
    method = build(:billing_payment_method, request_key: nil)
    expect(method).not_to be_valid
    expect(method.errors[:request_key]).to be_present
  end
end
