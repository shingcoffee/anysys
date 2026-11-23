# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Quota do
  it "uses deterministic finite Starter capacity without creating catalog or onboarding rows" do
    customer = create(:customer)
    quota = described_class.for(customer)
    before_counts = [Billing::Plan.count, Billing::Subscription.count, Billing::Settings.count, Billing::CountableItem.count]
    expect(quota.limit("entity")).to eq(25)
    expect(quota.limit("page")).to eq(50)
    expect(quota.limit("member")).to eq(5)
    expect(quota.allow?("entity")).to be(true)
    expect(Billing::Quota::Guard.check(customer: customer, item_key: "entity").allowed?).to be(true)
    expect([Billing::Plan.count, Billing::Subscription.count, Billing::Settings.count, Billing::CountableItem.count]).to eq(before_counts)
  end

  it "keeps purchased limits fixed across catalog changes and uses finite fallback after cancellation" do
    subscription = create(:billing_subscription)
    Billing::StandardPlans.seed!
    subscription.update!(plan_snapshot: subscription.plan_snapshot.merge("limits" => { "page" => 25, "entity" => 12, "member" => 3 }))
    quota = described_class.for(subscription.customer)
    Billing::AssignPlanLimits.call(plan: subscription.plan, limits: { "page" => 999 })
    expect(quota.limit("page")).to eq(25)
    Billing::Activities::CancelSubscription.call(subscription: subscription, immediately: true)
    expect(quota.limit("page")).to eq(10)
    expect(quota.limit("entity")).to eq(5)
    expect(quota.limit("member")).to eq(1)
  end

  it "uses bounded snapshot grace even when no renewal cron has run" do
    subscription = create(:billing_subscription, current_period_end: 1.day.ago)
    Billing::StandardPlans.seed!
    subscription.update!(plan_snapshot: subscription.plan_snapshot.merge("grace_period_days" => 2, "limits" => { "page" => 25 }))
    Billing::Settings.current.update!(grace_period_days: 99)
    expect(Billing::Entitlements.for(customer: subscription.customer).source).to eq(:grace)
    expect(Billing::Entitlements.for(customer: subscription.customer, at: 2.days.from_now).limits["page"]).to eq(10)
    expect(Billing::Settings.count).to eq(1)
  end

  it "never transfers the platform quota bypass to another tenant context" do
    tenant = create(:customer)
    platform = build(:customer, id: 81_721_200)
    Current.set(customer: platform) do
      expect(described_class.for(platform).limit("entity")).to eq(-1)
      expect(described_class.for(tenant).limit("entity")).to eq(25)
    end
  end

  it "honors an explicitly configured finite zero default instead of substituting Starter" do
    customer = create(:customer)
    configured = create(:billing_plan, :default_plan)
    Billing::AssignPlanLimits.call(plan: configured, limits: { page: 0, entity: 0, member: 0 })
    quota = described_class.for(customer)
    expect(quota.limit("page")).to eq(0)
    expect(quota.limit("entity")).to eq(0)
    expect(quota.limit("member")).to eq(0)
    expect(quota.allow?("page")).to be(false)
  end
end
