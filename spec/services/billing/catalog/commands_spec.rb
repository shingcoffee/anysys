# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Billing catalog commands" do
  it "preserves invalid price and limit input on the returned contract without syncing the model" do
    plan = create(:billing_plan)
    result = Billing::Catalog::SavePlan.call(plan: plan, params: { amount_usd: "12.345" }, limits: { "page" => "abc" })
    expect(result.status).to eq(:invalid)
    expect(result.form.amount_usd).to eq("12.345")
    expect(result.form.limits["page"]).to eq("abc")
    expect(result.errors[:limits]).to be_present
    expect(plan.reload.amount_usd).to eq(99)
    expect(plan.plan_limits.count).to eq(0)
  end

  it "swaps a valid finite free default atomically and refuses to archive it" do
    first = Billing::Catalog::SavePlan.call(plan: Billing::Plan.new,
      params: { code: "free1", name: "Free1", amount_usd: 0, amount_cny: 0, interval: "monthly", trial_days: 0, active: true, is_default: true, position: 0 },
      limits: { page: 10, entity: 5, member: 1 }).record
    second = create(:billing_plan, :free)
    invalid = Billing::Catalog::SavePlan.call(plan: second, params: { is_default: true }, limits: { page: -1, entity: 5, member: 1 })
    expect(invalid.status).to eq(:invalid)
    expect(first.reload.is_default).to be(true)
    valid = Billing::Catalog::SavePlan.call(plan: second, params: { is_default: true }, limits: { page: 10, entity: 5, member: 1 })
    expect(valid.status).to eq(:saved)
    expect(first.reload.is_default).to be(false)
    expect(Billing::Plan.where(is_default: true).count).to eq(1)
    expect(Billing::Catalog::ArchivePlan.call(plan: second).reason).to eq(:default_plan_required)
  end

  it "protects referenced price identity while allowing new limits without changing accepted entitlements" do
    subscription = create(:billing_subscription)
    invalid = Billing::Catalog::SavePlan.call(plan: subscription.plan, params: { amount_usd: 500 }, limits: {})
    expect(invalid.status).to eq(:invalid)
    original = subscription.plan_snapshot
    saved = Billing::Catalog::SavePlan.call(plan: subscription.plan, params: { name: "Catalog renamed" }, limits: { page: 7 })
    expect(saved.status).to eq(:saved)
    expect(subscription.reload.plan_snapshot).to eq(original)
    expect(Billing::Catalog::ArchivePlan.call(plan: subscription.plan).status).to eq(:archived)
    expect(subscription.plan.destroy).to be(false)
  end

  it "requires a supported fixed-coupon currency and preserves the invalid form" do
    coupon = build(:billing_coupon, :fixed)
    result = Billing::Catalog::SaveCoupon.call(coupon: coupon, params: { currency: "", amount_off_cents: "bad" })
    expect(result.status).to eq(:invalid)
    expect(result.form.amount_off_cents).to eq("bad")
    expect(result.form.errors[:currency]).to be_present
    expect(coupon).to be_new_record
  end

  it "enables any existing countable item" do
    item = Billing::CountableItem.create!(key: "storage", label: "Storage", enabled: false, period: "total")
    result = Billing::Catalog::UpdateCountableItems.call(items: [{ id: item.id, label: "Storage", enabled: "1", position: "0", period: "total" }])
    expect(result.status).to eq(:saved)
    expect(item.reload.enabled).to be(true)
  end
end
