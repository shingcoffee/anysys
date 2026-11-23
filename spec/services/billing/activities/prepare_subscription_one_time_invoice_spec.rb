# frozen_string_literal: true

require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::PrepareSubscriptionOneTimeInvoice do
  include BillingPartitionBHelpers

  it "returns an already-open payable invoice without mutating it" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    expect(invoice).to be_open

    result = described_class.call(customer: aggregate.fetch(:tenant), subscription: aggregate.fetch(:subscription))

    expect(result.status).to eq(:ready)
    expect(result.invoice).to eq(invoice)
    expect(invoice.reload.status).to eq("open")
    expect(invoice.number).to be_present
  end

  it "finalizes an accepted draft initial invoice so it can be paid once" do
    aggregate = billing_aggregate(finalize: false)
    draft = aggregate.fetch(:invoice)
    expect(draft).to be_draft

    result = described_class.call(customer: aggregate.fetch(:tenant), invoice_id: draft.id)

    expect(result.status).to eq(:ready)
    expect(result.invoice.reload).to be_open
    expect(result.invoice.total_cents).to be_positive
    expect(result.invoice.number).to be_present
  end

  it "finalizes an accepted draft proration invoice" do
    aggregate = billing_aggregate(purpose: "renewal")
    subscription = aggregate.fetch(:subscription)
    target = create(:billing_plan, amount_usd: 199)
    change = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: target, request_key: SecureRandom.uuid)
    expect(change.status).to eq(:awaiting_payment)
    draft = change.invoice
    expect(draft).to be_draft

    result = described_class.call(customer: aggregate.fetch(:tenant), invoice_id: draft.id)

    expect(result.status).to eq(:ready)
    expect(result.invoice.reload).to be_open
    expect(result.invoice.purpose).to eq("proration")
    expect(result.invoice.total_cents).to be_positive
  end

  it "materializes a due-now renewal invoice at the period boundary" do
    allow(Billing::Onboarding).to receive(:call)
    customer = create(:customer)
    subscription = create(:billing_subscription, customer: customer, current_period_start: 1.month.ago,
      current_period_end: Time.current, amount_cents: 10_000)

    result = described_class.call(customer: customer, subscription: subscription, at: Time.current)

    expect(result.status).to eq(:ready)
    expect(result.invoice.purpose).to eq("renewal")
    expect(result.invoice).to be_open
    expect(result.invoice.total_cents).to be_positive
    expect(result.invoice.period_start).to be_within(2.seconds).of(subscription.current_period_end)
  end

  it "rejects another tenant's invoice id" do
    aggregate = billing_aggregate
    stranger = create(:customer)

    result = described_class.call(customer: stranger, invoice_id: aggregate.fetch(:invoice).id)

    expect(result.status).to eq(:invalid)
    expect(result.reason).to eq(:invoice_not_payable)
    expect(result.invoice).to be_nil
  end

  it "returns a manual-mode open invoice without changing collection mode" do
    aggregate = billing_aggregate(mode: "manual")
    invoice = aggregate.fetch(:invoice)

    result = described_class.call(customer: aggregate.fetch(:tenant), invoice_id: invoice.id)

    expect(result.status).to eq(:ready)
    expect(result.invoice).to eq(invoice)
    expect(invoice.reload.effective_collection_mode).to eq("manual")
    expect(invoice).to be_open
  end

  it "returns an exhausted uncollectible invoice so one-time recovery can start" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    invoice.update!(status: "uncollectible", collection_state: "exhausted", attempt_count: 4)

    result = described_class.call(customer: aggregate.fetch(:tenant), subscription: aggregate.fetch(:subscription))

    expect(result.status).to eq(:ready)
    expect(result.invoice).to eq(invoice)
    expect(invoice.reload.status).to eq("uncollectible")
    expect(invoice.attempt_count).to eq(4)
  end
end
