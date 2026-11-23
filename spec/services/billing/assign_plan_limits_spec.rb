# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::AssignPlanLimits do
  it "rejects malformed or unsupported limits" do
    plan = create(:billing_plan)
    %w[abc 1.5].each do |raw|
      expect { described_class.call(plan: plan, limits: { "page" => raw }) }.to raise_error(ArgumentError)
    end
    expect { described_class.call(plan: plan, limits: { "storage" => "100" }) }.to raise_error(ArgumentError)
    expect(plan.plan_limits.count).to eq(0)
  end

  it "treats blank, unlimited, and any negative as unlimited" do
    plan = create(:billing_plan)
    described_class.call(plan: plan, limits: { "page" => "unlimited", "entity" => "-2", "member" => "" })
    expect(plan.plan_limits.find_by!(item_key: "page").limit_value).to eq(Billing::PlanLimit::UNLIMITED)
    expect(plan.plan_limits.find_by!(item_key: "entity").limit_value).to eq(Billing::PlanLimit::UNLIMITED)
    expect(plan.plan_limits.find_by!(item_key: "member").limit_value).to eq(Billing::PlanLimit::UNLIMITED)
  end

  it "supports an explicit paid-plan unlimited value and upserts finite limits" do
    plan = create(:billing_plan)
    described_class.call(plan: plan, limits: { "page" => "", "entity" => "5" })
    described_class.call(plan: plan, limits: { "entity" => "9" })
    expect(plan.plan_limits.find_by!(item_key: "page").limit_value).to eq(-1)
    expect(plan.plan_limits.find_by!(item_key: "entity").limit_value).to eq(9)
    expect(plan.plan_limits.count).to eq(2)
  end
end
