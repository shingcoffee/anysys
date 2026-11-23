# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Activities::Subscribe do
  let(:customer) { create(:customer) }
  let(:plan) { create(:billing_plan) }
  let(:key) { SecureRandom.uuid }

  before do
    allow(Billing::Onboarding).to receive(:call)
    Billing::Settings.current.update!(collection_mode: "manual", grace_period_days: 7)
    create(:billing_plan, :default_plan)
  end

  it "persists pending enrollment, fixed dates and finite fallback until manual settlement" do
    freeze_time do
      result = described_class.call(customer: customer, plan: plan, request_key: key)
      expect(result.status).to eq(:awaiting_payment)
      expect(result.subscription.status).to eq("pending")
      expect(result.subscription.current_period_start).to eq(Time.current)
      expect(Billing::Entitlements.for(customer: customer).source).to eq(:free)
      Billing::Activities::FinalizeInvoice.call(invoice: result.invoice)
      expect(result.subscription.reload.status).to eq("pending")
      owner = find_or_create_platform_owner
      Billing::Activities::MarkInvoicePaid.call(invoice: result.invoice, source: :manual, actor: owner, reference: "bank-1")
      expect(result.subscription.reload.status).to eq("active")
    end
  end

  it "settles a free initial invoice through the same projection hook" do
    result = described_class.call(customer: customer, plan: create(:billing_plan, :free), request_key: key)
    Billing::Activities::FinalizeInvoice.call(invoice: result.invoice)
    expect(result.invoice.reload.status).to eq("paid")
    expect(result.subscription.reload.status).to eq("active")
    expect(result.invoice.entitlements_applied_at).to be_present
  end

  it "does not reenroll or create an invoice when a historical key is replayed" do
    first = described_class.call(customer: customer, plan: plan, request_key: key)
    Billing::Activities::CancelSubscription.call(subscription: first.subscription, immediately: true)
    expect {
      replay = described_class.call(customer: customer, plan: plan, request_key: key)
      expect(replay.status).to eq(:unchanged)
      expect(replay.subscription.id).to eq(first.subscription.id)
    }.not_to change(Billing::Invoice, :count)
  end

  it "grants a paid trial at most once across cancellation and reenrollment" do
    trial_plan = create(:billing_plan, :with_trial)
    first = described_class.call(customer: customer, plan: trial_plan, request_key: key)
    expect(first.status).to eq(:trialing)
    expect(customer.reload.trial_used_at).to be_present
    Billing::Activities::CancelSubscription.call(subscription: first.subscription, immediately: true)
    second = described_class.call(customer: customer, plan: trial_plan, request_key: SecureRandom.uuid)
    expect(second.status).to eq(:awaiting_payment)
    expect(second.subscription.trial_end).to be_nil
  end

  it "rejects an invalid coupon without silently enrolling at undiscounted price" do
    exhausted = create(:billing_coupon, max_redemptions: 1, times_redeemed: 1)
    expect {
      result = described_class.call(customer: customer, plan: plan, coupon: exhausted, request_key: key)
      expect(result.status).to eq(:invalid)
      expect(result.form.errors[:coupon_code]).to be_present
    }.not_to change(Billing::Subscription, :count)
  end

  it "explicitly reenrolls after logical initial expiry even if cron has not run" do
    first = described_class.call(customer: customer, plan: plan, request_key: key)
    Billing::Activities::FinalizeInvoice.call(invoice: first.invoice)
    deadline = Billing::PlanChangePolicy.grace_deadline(first.invoice)
    travel_to(deadline + 1.second) do
      next_request = described_class.call(customer: customer, plan: plan, request_key: SecureRandom.uuid)
      expect(next_request.status).to eq(:awaiting_payment)
      expect(next_request.subscription.id).not_to eq(first.subscription.id)
      expect(first.subscription.reload.status).to eq("expired")
      expect(first.invoice.reload.status).to eq("open")
      expect(Billing::Subscription.where(customer_id: customer.id).live.count).to eq(1)
    end
  end

  it "admits initial enrollment with finite Starter fallback when the catalog default is absent" do
    Billing::Plan.default_plan.destroy!
    result = described_class.call(customer: customer, plan: plan, request_key: key)
    expect(result.status).to eq(:awaiting_payment)
    expect(result.subscription.request_key).to eq(key)
    expect(Billing::Invoice.where(customer_id: customer.id).count).to eq(1)
    fallback = Billing::Entitlements.for(customer: customer)
    expect(fallback.reason).to be_nil
    expect(fallback.limits).to eq("page" => 50, "entity" => 25, "member" => 5)
  end

  it "returns a contract error rather than raising when no enrollment plan is configured" do
    result = described_class.call(customer: customer, plan: nil, request_key: key)
    expect(result.status).to eq(:invalid)
    expect(result.errors[:plan_code]).to be_present
    expect(Billing::Subscription.where(customer_id: customer.id).count).to eq(0)
  end

  it "does not end a legitimately renewable overdue base within its saved grace" do
    existing = create(:billing_subscription, customer: customer, current_period_start: 1.month.ago,
      current_period_end: 1.day.ago, plan_snapshot: Billing::PlanChangePolicy.snapshot(plan: plan, currency: "USD"))
    result = described_class.call(customer: customer, plan: plan, request_key: key)
    expect(result.status).to eq(:unchanged)
    expect(result.subscription.id).to eq(existing.id)
    expect(existing.reload.status).to eq("active")
    expect(existing.invoices.count).to eq(0)
  end
end
