# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::MarkInvoicePaid do
  include BillingPartitionBHelpers

  it "requires a platform owner and a manual operator reference" do
    aggregate = billing_aggregate(mode: "manual")
    invoice = aggregate.fetch(:invoice)
    expect(described_class.call(invoice: invoice, source: :manual, actor: aggregate.fetch(:actor), reference: "bank-1").reason).to eq(:owner_required)
    owner = find_or_create_platform_owner
    expect(described_class.call(invoice: invoice, source: :manual, actor: owner).reason).to eq(:settlement_reference_required)
    expect(invoice.reload.status).to eq("open")
    result = described_class.call(invoice: invoice, source: :manual, actor: owner, reference: "bank-1", note: "Matched remittance")
    expect(result.status).to eq(:paid)
    expect(invoice.reload.settlement_reference).to eq("bank-1")
    expect(invoice.settled_by_id).to eq(owner.id)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
  end

  it "refuses manual settlement while a real PSP attempt is unresolved" do
    aggregate = billing_aggregate
    billing_payment(aggregate, state: "unknown")
    result = described_class.call(invoice: aggregate.fetch(:invoice), source: :manual,
      actor: find_or_create_platform_owner, reference: "bank-1")
    expect(result.reason).to eq(:collection_in_flight)
    expect(aggregate.fetch(:subscription).reload.status).to eq("pending")
  end

  it "settles uncollectible debt once and records a second genuine capture for owner review" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    invoice.update!(status: "uncollectible", collection_state: "exhausted")
    payment = billing_payment(aggregate)
    expect(described_class.call(invoice: invoice, source: :gateway, payment: payment).status).to eq(:paid)
    expect(described_class.call(invoice: invoice, source: :gateway, payment: payment).status).to eq(:unchanged)
    second = billing_payment(aggregate, ordinal: 2)
    expect(described_class.call(invoice: invoice, source: :gateway, payment: second).reason).to eq(:duplicate_capture)
    expect(invoice.reload.payment_id).to eq(payment.id)
    expect(invoice.settlement_review_code).to eq("duplicate_capture")
    expect(Billing::Notice.where(kind: "payment_succeeded", billing_invoice_id: invoice.id).count).to eq(1)
  end

  it "records late money without reviving an explicitly ended subscription" do
    aggregate = billing_aggregate
    aggregate.fetch(:subscription).update!(status: "expired", ended_at: Time.current)
    payment = billing_payment(aggregate)
    result = described_class.call(invoice: aggregate.fetch(:invoice), source: :gateway, payment: payment)
    expect(result.status).to eq(:review_required)
    expect(aggregate.fetch(:invoice).reload.status).to eq("paid")
    expect(aggregate.fetch(:subscription).reload.status).to eq("expired")
  end

  it "rejects a captured payment belonging to another tenant invoice" do
    first = billing_aggregate
    other = billing_aggregate
    payment = billing_payment(other)
    expect(described_class.call(invoice: first.fetch(:invoice), source: :gateway, payment: payment).reason).to eq(:payment_mismatch)
    expect(first.fetch(:invoice).reload.status).to eq("open")
  end

  it "redrives a paid invoice missing A's settlement receipt without charging or issuing another notice" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    payment = billing_payment(aggregate)
    invoice.update!(status: "paid", payment_id: payment.id, paid_at: payment.paid_at, settlement_source: "gateway", collection_state: "settled")
    expect(aggregate.fetch(:subscription).reload.status).to eq("pending")
    expect(described_class.call(invoice: invoice, payment: payment, source: :gateway).status).to eq(:paid)
    expect(aggregate.fetch(:subscription).reload.status).to eq("active")
    expect(invoice.reload.entitlements_applied_at).to eq(payment.paid_at)
    expect(described_class.call(invoice: invoice, payment: payment, source: :gateway).status).to eq(:unchanged)
    expect(Billing::Notice.where(event_key: "invoice_paid:#{invoice.id}").count).to eq(1)
  end
end
