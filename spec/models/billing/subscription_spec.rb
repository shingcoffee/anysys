# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Subscription do
  it "includes pending in both the live query and database uniqueness predicate" do
    first = create(:billing_subscription, status: "pending")
    expect(described_class.live).to include(first)
    expect { create(:billing_subscription, customer: first.customer) }.to raise_error(ActiveRecord::RecordNotUnique)
    first.update!(status: "cancelled")
    expect { create(:billing_subscription, customer: first.customer) }.not_to raise_error
  end

  it "protects invoice history from subscription destruction" do
    subscription = create(:billing_subscription)
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :initial, idempotency_key: "history",
      period_start: subscription.current_period_start, period_end: subscription.current_period_end,
      terms_snapshot: Billing::PlanChangePolicy.invoice_terms(subscription.plan_snapshot, due_at: Time.current))
    expect(subscription.destroy).to be(false)
    expect(Billing::Invoice.exists?(invoice.id)).to be(true)
  end

  it "retains the original 31st through February and into March" do
    subscription = build(:billing_subscription, billing_anchor_day: 31, billing_anchor_month: 1)
    january = Time.zone.parse("2027-01-31 09:30:00")
    february = subscription.period_end_from(january)
    expect(february.day).to eq(28)
    expect(subscription.period_end_from(february)).to eq(Time.zone.parse("2027-03-31 09:30:00"))
  end
end
