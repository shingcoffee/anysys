# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Activities::ChangePlan do
  let(:subscription) { create(:billing_subscription, current_period_start: 15.days.ago, current_period_end: 15.days.from_now) }
  let(:target) { create(:billing_plan, amount_usd: 199) }
  let(:key) { SecureRandom.uuid }

  it "preserves the purchased snapshot and one invoice across manual unpaid resubmits" do
    result = described_class.call(subscription: subscription, new_plan: target, request_key: key)
    Billing::Activities::FinalizeInvoice.call(invoice: result.invoice)
    expect(result.status).to eq(:awaiting_payment)
    expect(subscription.reload.amount_cents).to eq(9900)
    replay = described_class.call(subscription: subscription, new_plan: target, request_key: SecureRandom.uuid)
    expect(replay.plan_change.id).to eq(result.plan_change.id)
    expect(replay.invoice.id).to eq(result.invoice.id)
    expect(subscription.plan_changes.count).to eq(1)
    expect(result.invoice.due_at).to eq(subscription.current_period_end)
  end

  it "applies an accepted archived target once, only after its invoice is paid" do
    result = described_class.call(subscription: subscription, new_plan: target, request_key: key)
    Billing::Catalog::ArchivePlan.call(plan: target)
    Billing::Activities::FinalizeInvoice.call(invoice: result.invoice)
    owner = find_or_create_platform_owner
    paid = Billing::Activities::MarkInvoicePaid.call(invoice: result.invoice, source: :manual, actor: owner, reference: "bank-2")
    expect(paid.status).to eq(:paid)
    expect(subscription.reload.amount_cents).to eq(19900)
    expect(result.plan_change.reload.status).to eq("applied")
    replay = described_class.call(subscription: subscription, new_plan: target, request_key: key)
    expect(replay.status).to eq(:applied)
    expect(subscription.invoices.count).to eq(1)
  end

  it "rejects a different outstanding target and a terminal request-key reuse" do
    first = described_class.call(subscription: subscription, new_plan: target, request_key: key)
    other = create(:billing_plan, amount_usd: 299)
    conflict = described_class.call(subscription: subscription, new_plan: other, request_key: SecureRandom.uuid)
    expect(conflict.reason).to eq(:pending_change_exists)
    Billing::Activities::CancelPlanChange.call(subscription: subscription, plan_change: first.plan_change)
    replay = described_class.call(subscription: subscription, new_plan: other, request_key: key)
    expect(replay.status).to eq(:unchanged)
    expect(replay.plan_change.status).to eq("cancelled")
    expect(subscription.invoices.count).to eq(1)
  end

  it "schedules downgrades, equal prices and any cadence change without a proration" do
    [create(:billing_plan, amount_usd: 49), create(:billing_plan), create(:billing_plan, :yearly, amount_usd: 999)].each do |plan|
      result = described_class.call(subscription: subscription, new_plan: plan, request_key: SecureRandom.uuid)
      expect(result.status).to eq(:scheduled)
      expect(result.plan_change.effective_at).to eq(subscription.current_period_end)
      expect(result.invoice).to be_nil
      Billing::Activities::CancelPlanChange.call(subscription: subscription, plan_change: result.plan_change)
    end
    expect(subscription.invoices.count).to eq(0)
  end

  it "does not grant another trial when moving from free onboarding to paid" do
    subscription.update!(amount_cents: 0, plan_snapshot: subscription.plan_snapshot.merge("amount_cents" => 0))
    result = described_class.call(subscription: subscription, new_plan: create(:billing_plan, :with_trial), request_key: key)
    expect(result.status).to eq(:awaiting_payment)
    expect(subscription.reload.trial_end).to be_nil
  end

  %w[pending past_due paused].each do |status|
    it "rejects new changes in #{status} state" do
      subscription.update!(status: status)
      expect(described_class.call(subscription: subscription, new_plan: target, request_key: key).reason).to eq(:change_requires_active_subscription)
    end
  end
end
