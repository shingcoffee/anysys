# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PlanLimit, type: :model do
  let(:plan) { create(:billing_plan) }

  def build_limit(limit_value:, item_key: "flowcharts")
    described_class.new(billing_plan_id: plan.id, item_key: item_key, limit_value: limit_value)
  end

  describe "associations" do
    it "belongs to a plan" do
      limit = described_class.create!(billing_plan_id: plan.id, item_key: "flowcharts", limit_value: 10)
      expect(limit.plan).to eq(plan)
    end
  end

  describe "validations" do
    it "requires item_key" do
      limit = build_limit(item_key: nil, limit_value: 5)
      expect(limit).not_to be_valid
      expect(limit.errors[:item_key]).to be_present
    end

    it "enforces uniqueness of item_key scoped to billing_plan_id" do
      described_class.create!(billing_plan_id: plan.id, item_key: "flowcharts", limit_value: 5)
      dup = build_limit(limit_value: 10)
      expect(dup).not_to be_valid
      expect(dup.errors[:item_key]).to be_present
    end

    it "allows the same item_key for different plans" do
      other_plan = create(:billing_plan)
      described_class.create!(billing_plan_id: plan.id,       item_key: "flowcharts", limit_value: 5)
      limit2     = described_class.new(billing_plan_id: other_plan.id, item_key: "flowcharts", limit_value: 10)
      expect(limit2).to be_valid
    end

    it "requires limit_value >= -1" do
      expect(build_limit(item_key: "x", limit_value: -2)).not_to be_valid
      expect(build_limit(item_key: "x", limit_value: -1)).to be_valid
      expect(build_limit(item_key: "x", limit_value:  0)).to be_valid
      expect(build_limit(item_key: "x", limit_value: 50)).to be_valid
    end

    it "requires limit_value to be an integer" do
      expect(build_limit(item_key: "x", limit_value: 1.5)).not_to be_valid
    end
  end

  describe "#unlimited?" do
    it "returns true when limit_value is -1 (UNLIMITED sentinel)" do
      expect(build_limit(limit_value: -1).unlimited?).to be true
    end

    it "returns false when limit_value is a positive integer" do
      expect(build_limit(limit_value: 10).unlimited?).to be false
    end

    it "returns false when limit_value is 0" do
      expect(build_limit(limit_value: 0).unlimited?).to be false
    end
  end

  describe "UNLIMITED constant" do
    it "is -1" do
      expect(described_class::UNLIMITED).to eq(-1)
    end
  end
end
