# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Activities::CancelSubscription do
  let(:subscription) { create(:billing_subscription) }

  it "cancels scheduled changes, retains paid access, and resumes only the cancellation flag" do
    target = create(:billing_plan, amount_usd: 29)
    change = Billing::Activities::ChangePlan.call(subscription: subscription, new_plan: target, request_key: SecureRandom.uuid).plan_change
    expect(described_class.call(subscription: subscription).status).to eq(:scheduled)
    expect(change.reload.status).to eq("cancelled")
    expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:purchased)
    expect(Billing::Activities::ResumeSubscription.call(subscription: subscription).status).to eq(:resumed)
    expect(change.reload.status).to eq("cancelled")
    expect(subscription.pending_plan_change).to be_nil
  end

  it "retains genuine renewal debt on immediate cancellation" do
    subscription.update!(current_period_end: Time.current)
    invoice = Billing::Renewal.prepare(subscription: subscription).invoice
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    described_class.call(subscription: subscription, immediately: true)
    expect(invoice.reload.status).to eq("open")
    expect(subscription.reload.status).to eq("cancelled")
    expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:free)
    expect(Billing::Activities::ResumeSubscription.call(subscription: subscription).status).to eq(:invalid)
  end

  it "does not clear overdue or paused state through Resume" do
    subscription.update!(status: "paused", cancel_at_period_end: true)
    expect(Billing::Activities::ResumeSubscription.call(subscription: subscription).reason).to eq(:resume_blocked)
    expect(subscription.reload.status).to eq("paused")
  end
end
