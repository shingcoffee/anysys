# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::GenerateInvoice do
  include BillingPartitionBHelpers

  it "reuses the permanent identity without replacing issued lines or policy" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    result = described_class.call(subscription: aggregate.fetch(:subscription), purpose: :initial,
      idempotency_key: invoice.idempotency_key, period_start: 1.day.from_now, period_end: 2.months.from_now,
      terms_snapshot: aggregate.fetch(:terms).merge("amount_cents" => 999_999), extra_line_items: [])
    expect(result.id).to eq(invoice.id)
    expect(result.line_items.pluck(:amount_cents)).to eq([10_000])
    expect(result.terms_snapshot.fetch("amount_cents")).to eq(10_000)
  end

  it "uses only supplied proration lines, with the accepted due date" do
    aggregate = billing_aggregate
    invoice = described_class.call(subscription: aggregate.fetch(:subscription), purpose: :proration,
      idempotency_key: "proration-test", period_start: 1.week.ago, period_end: 1.month.from_now,
      terms_snapshot: aggregate.fetch(:invoice).terms_snapshot,
      extra_line_items: [{ description: "Proration", kind: "proration", quantity: 1, unit_amount_cents: 500, amount_cents: 500 }])
    expect(invoice.line_items.pluck(:kind)).to eq(["proration"])
    expect(invoice.due_at).to eq(aggregate.fetch(:invoice).due_at)
  end

  it "honors A's proration period-end deadline and never substitutes current global policy" do
    aggregate = billing_aggregate
    subscription = aggregate.fetch(:subscription)
    accepted = aggregate.fetch(:invoice).terms_snapshot.merge("due_at" => subscription.current_period_end.iso8601(6), "dunning_schedule" => [])
    Billing::Settings.current.update!(collection_mode: "manual", dunning_schedule: [2, 4], grace_period_days: 1)
    invoice = described_class.call(subscription: subscription, purpose: :proration, idempotency_key: "accepted-proration",
      period_start: subscription.current_period_start, period_end: subscription.current_period_end, terms_snapshot: accepted,
      extra_line_items: [{ description: "Proration", kind: "proration", quantity: 1, unit_amount_cents: 1000, amount_cents: 1000 }])
    expect(invoice.due_at).to eq(subscription.current_period_end)
    expect(invoice.terms_snapshot).to eq(accepted)
    expect(invoice.collection_deadline).to eq(subscription.current_period_end + 14.days)
  end
end
