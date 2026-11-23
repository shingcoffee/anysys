# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Cron::RenewSubscriptions do
  it "prepares one invoice across repeated passes without granting an unpaid renewal" do
    sub = create(:billing_subscription, current_period_start: 1.month.ago, current_period_end: Time.current)
    other = create(:customer)
    Current.set(customer: other) do
      2.times { described_class.perform }
      expect(Current.customer).to eq(other)
    end
    expect(sub.invoices.count).to eq(1)
    expect(sub.reload.current_period_end).to eq(sub.invoices.first.period_start)
  end

  it "expires a scheduled cancellation at its actual boundary" do
    sub = create(:billing_subscription, current_period_start: 1.month.ago, current_period_end: Time.current, cancel_at_period_end: true)
    described_class.perform
    expect(sub.reload.status).to eq("expired")
    expect(sub.invoices.count).to eq(0)
  end

  it "does not invoice paused subscriptions" do
    sub = create(:billing_subscription, status: "paused", current_period_end: 1.day.ago)
    described_class.perform
    expect(sub.invoices.count).to eq(0)
    expect(sub.reload.status).to eq("paused")
  end
end
