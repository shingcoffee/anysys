# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Activities::FinalizeInvoice do
  include BillingPartitionBHelpers

  it "preserves number, lines, due date and snapshot on repeated finalization" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    before = invoice.attributes.slice(*Billing::Invoice::FINANCIAL_ATTRIBUTES)
    lines = invoice.line_items.pluck(:id, :amount_cents)
    Billing::Settings.current.update!(tax_rate_bps: 1000, collection_mode: "manual", dunning_schedule: [])
    expect { described_class.call(invoice: invoice) }.not_to change(Billing::Notice, :count)
    expect(invoice.reload.attributes.slice(*Billing::Invoice::FINANCIAL_ATTRIBUTES)).to eq(before)
    expect(invoice.line_items.pluck(:id, :amount_cents)).to eq(lines)
  end

  it "reserves exactly one redemption cycle and taxes the discounted subtotal with integer math" do
    aggregate = billing_aggregate
    subscription = aggregate.fetch(:subscription)
    coupon = create(:billing_coupon, percent_off: 20, duration: "once")
    Billing::Activities::ApplyCoupon.call(subscription: subscription, coupon: coupon)
    terms = aggregate.fetch(:invoice).terms_snapshot.merge("tax_rate_bps" => 625)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :renewal,
      idempotency_key: "coupon-cycle", period_start: subscription.current_period_end,
      period_end: subscription.current_period_end + 1.month, terms_snapshot: terms)
    2.times { described_class.call(invoice: invoice) }
    expect(invoice.reload.discount_cents).to eq(2000)
    expect(invoice.tax_cents).to eq(500)
    expect(invoice.total_cents).to eq(8500)
    expect(subscription.coupon_redemption.reload.cycles_used).to eq(1)
    expect(invoice.line_items.where(kind: "discount").count).to eq(1)
  end

  it "settles a free initial invoice through the subscription hook without a PSP attempt" do
    aggregate = billing_aggregate
    subscription = aggregate.fetch(:subscription)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :initial,
      idempotency_key: "free-initial", period_start: subscription.current_period_start,
      period_end: subscription.current_period_end, terms_snapshot: aggregate.fetch(:invoice).terms_snapshot.merge("amount_cents" => 0))
    expect { described_class.call(invoice: invoice) }.not_to change(Payments::Payment, :count)
    expect(invoice.reload.status).to eq("paid")
    expect(invoice.settlement_source).to eq("zero")
    expect(subscription.reload.status).to eq("active")
  end
end
