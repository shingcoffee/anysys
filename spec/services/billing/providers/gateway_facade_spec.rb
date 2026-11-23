# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Payments::Gateway do
  include BillingPartitionBHelpers

  it "queries the committed historical merchant despite disablement and a different current mode" do
    aggregate = billing_aggregate
    payment = billing_payment(aggregate, state: "unknown")
    account = aggregate.fetch(:account)
    account.update!(status: "disabled")
    gateway = instance_double(Payments::Gateways::Stripe)
    expect(Payments::Gateways::Stripe).to receive(:new).with(account: account).and_return(gateway)
    expect(gateway).to receive(:billing_query).with(payment: payment).and_return(status: :pending)
    allow(Payments::CredentialResolver).to receive(:default_mode).and_return("production")
    expect(described_class.billing_query(customer: aggregate.fetch(:platform), payment: payment, merchant_account: account)).to eq(status: :pending)
  end

  it "refuses an explicit merchant that differs from the committed payment identity" do
    aggregate = billing_aggregate
    payment = billing_payment(aggregate, state: "unknown")
    other = create(:payment_merchant_account, :stripe, :production, customer: aggregate.fetch(:platform))
    expect { described_class.billing_query(customer: aggregate.fetch(:platform), payment: payment, merchant_account: other) }.to raise_error(Payments::Errors::TenantMismatch)
  end

  it "does not fall back to current credentials when billing cleanup lacks a pinned merchant" do
    aggregate = billing_aggregate
    expect { described_class.detach_token(customer: aggregate.fetch(:platform), payment_method: aggregate.fetch(:token)) }.to raise_error(Payments::Errors::CredentialsMissing)
  end
end
