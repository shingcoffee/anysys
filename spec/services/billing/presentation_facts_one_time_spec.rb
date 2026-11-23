# frozen_string_literal: true

require "rails_helper"
require_relative "partition_b_helpers"

RSpec.describe Billing::PresentationFacts do
  include BillingPartitionBHelpers

  before { allow(Billing::Onboarding).to receive(:call) }

  def facts_for(invoice, **kwargs)
    described_class.invoice_collection(invoice: invoice, **kwargs)
  end

  it "offers one-time payment for open invoices including manual collection" do
    gateway = billing_aggregate
    manual = billing_aggregate(mode: "manual")
    expect(facts_for(gateway.fetch(:invoice))).to include(can_pay_one_time: true)
    expect(facts_for(manual.fetch(:invoice))).to include(can_pay_one_time: true, effective_mode: "manual")
  end

  it "offers one-time payment for exhausted uncollectible invoices" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    invoice.update!(status: "uncollectible", collection_state: "exhausted", attempt_count: 4)
    expect(facts_for(invoice.reload)).to include(can_pay_one_time: true, state: "exhausted", failed_attempts: 4)
  end

  it "hides one-time payment on paid, void, and draft invoices" do
    paid = billing_aggregate.fetch(:invoice)
    paid.update!(status: "paid", collection_state: "settled", paid_at: Time.current)
    voided = billing_aggregate.fetch(:invoice)
    voided.update!(status: "void")
    draft = billing_aggregate(finalize: false).fetch(:invoice)
    expect(facts_for(paid.reload)[:can_pay_one_time]).to be(false)
    expect(facts_for(voided.reload)[:can_pay_one_time]).to be(false)
    expect(facts_for(draft.reload)[:can_pay_one_time]).to be(false)
  end

  it "blocks one-time payment while an off-session collection attempt is inflight" do
    aggregate = billing_aggregate
    billing_payment(aggregate, state: "pending")
    expect(facts_for(aggregate.fetch(:invoice))).to include(can_pay_one_time: false, unresolved: true)
  end

  it "still offers one-time payment while a prior one-time attempt is inflight" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    invoice.collection_attempts.create!(customer_id: invoice.customer_id, ordinal: 1, request_key: "bi-open-#{invoice.id}",
      merchant_account: aggregate.fetch(:account), billing_payment_method_id: nil, state: "pending")
    expect(facts_for(invoice.reload)).to include(can_pay_one_time: true)
  end

  it "projects the current unpaid invoice ahead of drafts and due renewals" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    allow(Billing::OneTimeProviders).to receive(:options).and_return([{ key: "stripe" }])

    projection = described_class.subscription_one_time_payment(
      subscription: aggregate.fetch(:subscription), invoices: [invoice])
    expect(projection).to include(kind: :unpaid_invoice, invoice_id: invoice.id, invoice_number: invoice.number,
      amount_cents: invoice.total_cents, currency: "USD")
    expect(projection[:providers]).to eq([{ key: "stripe" }])
  end

  it "projects an accepted draft initial invoice without writing rows" do
    aggregate = billing_aggregate(finalize: false)
    draft = aggregate.fetch(:invoice)
    expect(draft).to be_draft
    allow(Billing::OneTimeProviders).to receive(:options).and_return([])

    expect do
      projection = described_class.subscription_one_time_payment(
        subscription: aggregate.fetch(:subscription), invoices: [])
      expect(projection).to include(kind: :draft_initial, invoice_id: draft.id, invoice_number: nil,
        amount_cents: draft.line_items.where(kind: %w[subscription proration]).sum(:amount_cents), currency: "USD")
    end.not_to change { draft.reload.status }
  end

  it "projects a due-now renewal from the accepted snapshot without creating an invoice" do
    aggregate = billing_aggregate(purpose: "renewal")
    subscription = aggregate.fetch(:subscription)
    aggregate.fetch(:invoice).update!(status: "paid", collection_state: "settled", paid_at: 1.month.ago)
    subscription.update!(current_period_end: 1.minute.ago, amount_cents: 10_000)
    allow(Billing::OneTimeProviders).to receive(:options).and_return([{ key: "stripe" }])

    expect do
      projection = described_class.subscription_one_time_payment(subscription: subscription.reload, invoices: [], at: Time.current)
      expect(projection).to include(kind: :renewal, invoice_id: nil, amount_cents: 10_000, currency: "USD")
      expect(projection[:period_start]).to be_within(2.seconds).of(subscription.current_period_end)
    end.not_to change(Billing::Invoice, :count)
  end

  it "delegates provider options to OneTimeProviders" do
    expect(Billing::OneTimeProviders).to receive(:options).with(currency: "CNY").and_return([{ key: "alipay" }])
    expect(described_class.one_time_provider_options(currency: "CNY")).to eq([{ key: "alipay" }])
  end
end
