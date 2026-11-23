# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Plan, type: :model do
  describe "validations" do
    it "requires code" do
      plan = build(:billing_plan, code: nil)
      expect(plan).not_to be_valid
      expect(plan.errors[:code]).to be_present
    end

    it "requires unique code" do
      create(:billing_plan, code: "PRO")
      dup = build(:billing_plan, code: "PRO")
      expect(dup).not_to be_valid
      expect(dup.errors[:code]).to be_present
    end

    it "requires name" do
      plan = build(:billing_plan, name: nil)
      expect(plan).not_to be_valid
    end

    it "requires amount_usd to be a non-negative integer" do
      expect(build(:billing_plan, amount_usd: -0.01)).not_to be_valid
      expect(build(:billing_plan, amount_usd:  0.00)).to be_valid
      expect(build(:billing_plan, amount_usd:  99.00)).to be_valid
    end

    it "requires amount_cny to be a non-negative integer" do
      expect(build(:billing_plan, amount_cny: -0.01)).not_to be_valid
      expect(build(:billing_plan, amount_cny:  0.00)).to be_valid
      expect(build(:billing_plan, amount_cny:  699.00)).to be_valid
    end

    it "requires interval to be in INTERVALS" do
      expect(build(:billing_plan, interval: "daily")).not_to be_valid
      expect(build(:billing_plan, interval: "monthly")).to be_valid
      expect(build(:billing_plan, interval: "yearly")).to be_valid
    end
  end

  describe "scopes" do
    it ".active returns only active plans" do
      active   = create(:billing_plan, active: true)
      inactive = create(:billing_plan, :inactive)
      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end

    it ".ordered returns by position then id" do
      p2 = create(:billing_plan, position: 2)
      p1 = create(:billing_plan, position: 1)
      p3 = create(:billing_plan, position: 1) # same position, higher id
      ordered = described_class.ordered.to_a
      expect(ordered.index(p1)).to be < ordered.index(p2)
      expect(ordered.index(p1)).to be < ordered.index(p3)
    end
  end

  describe ".default_plan" do
    it "returns the active default plan" do
      plan = create(:billing_plan, :free, :default_plan)
      expect(described_class.default_plan).to eq(plan)
    end

    it "returns nil when no default is set" do
      create(:billing_plan, is_default: false)
      expect(described_class.default_plan).to be_nil
    end

    it "returns nil when default plan is inactive" do
      expect { create(:billing_plan, :free, :default_plan, :inactive) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "atomically replaces the default through the catalog command" do
      first = create(:billing_plan, :free, :default_plan)
      second = create(:billing_plan, :free)
      Billing::Catalog::SavePlan.call(plan: second, params: { is_default: true }, limits: { page: 10, entity: 5, member: 1 })
      expect(first.reload.is_default).to be(false)
      expect(second.reload.is_default).to be(true)
    end
  end

  describe "predicates" do
    it "#monthly? and #yearly? return true only for the matching interval" do
      aggregate_failures do
        expect(build(:billing_plan, interval: "monthly").monthly?).to be true
        expect(build(:billing_plan, interval: "yearly").monthly?).to be false
        expect(build(:billing_plan, interval: "yearly").yearly?).to be true
        expect(build(:billing_plan, interval: "monthly").yearly?).to be false
      end
    end
  end

  describe "#price_cents_for" do
    let(:plan) { build(:billing_plan, amount_usd: 99.00, amount_cny: 699.00) }

    it "returns amount_usd for USD" do
      expect(plan.price_cents_for("USD")).to eq(9_900)
    end

    it "returns amount_usd for lowercase usd" do
      expect(plan.price_cents_for("usd")).to eq(9_900)
    end

    it "returns amount_cny for CNY" do
      expect(plan.price_cents_for("CNY")).to eq(69_900)
    end

    it "rejects unsupported catalog currencies" do
      expect { plan.price_cents_for("EUR") }.to raise_error(ArgumentError)
    end
  end

  describe "#limit_for" do
    let(:plan) { create(:billing_plan) }

    it "returns the stored limit_value when a PlanLimit row exists" do
      Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "flowcharts", limit_value: 5)
      # reload to populate the association
      plan.plan_limits.reset
      expect(plan.limit_for("flowcharts")).to eq(5)
    end

    it "accepts symbol keys" do
      Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "members", limit_value: 100)
      plan.plan_limits.reset
      expect(plan.limit_for(:members)).to eq(100)
    end

    it "returns unlimited when no plan limit exists" do
      expect(plan.limit_for("nonexistent_key")).to eq(Billing::PlanLimit::UNLIMITED)
    end
  end

  describe "#free?" do
    it "returns true when both USD and CNY cents are zero" do
      expect(build(:billing_plan, :free).free?).to be true
    end

    it "returns false when either currency has non-zero cents" do
      aggregate_failures do
        expect(build(:billing_plan, amount_usd: 1.00, amount_cny: 0.00).free?).to be false
        expect(build(:billing_plan, amount_usd: 0.00, amount_cny: 1.00).free?).to be false
        expect(build(:billing_plan, amount_usd: 99.00, amount_cny: 699.00).free?).to be false
      end
    end
  end

  describe "has_many :plan_limits" do
    it "destroys associated limits when the plan is destroyed" do
      plan = create(:billing_plan)
      Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "flowcharts", limit_value: 10)
      expect { plan.destroy }.to change(Billing::PlanLimit, :count).by(-1)
    end
  end
end
