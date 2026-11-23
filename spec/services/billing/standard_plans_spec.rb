# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::StandardPlans do
  before do
    Billing::PlanLimit.delete_all
    Billing::Plan.delete_all
    Billing::CountableItem.delete_all
  end

  describe ".seed!" do
    it "creates exactly 4 plans" do
      described_class.seed!
      expect(Billing::Plan.count).to eq(4)
    end

    it "creates plans with the expected codes" do
      described_class.seed!
      codes = Billing::Plan.pluck(:code)
      expect(codes).to contain_exactly(
        "free", "starter-monthly", "pro-monthly", "enterprise-monthly"
      )
    end

    it "sets dual USD prices correctly" do
      described_class.seed!
      expect(Billing::Plan.find_by!(code: "free").amount_usd).to eq(0.00)
      expect(Billing::Plan.find_by!(code: "starter-monthly").amount_usd).to eq(29.00)
      expect(Billing::Plan.find_by!(code: "pro-monthly").amount_usd).to eq(99.00)
      expect(Billing::Plan.find_by!(code: "enterprise-monthly").amount_usd).to eq(499.00)
    end

    it "sets dual CNY prices correctly" do
      described_class.seed!
      expect(Billing::Plan.find_by!(code: "free").amount_cny).to eq(0.00)
      expect(Billing::Plan.find_by!(code: "starter-monthly").amount_cny).to eq(299.00)
      expect(Billing::Plan.find_by!(code: "pro-monthly").amount_cny).to eq(999.00)
      expect(Billing::Plan.find_by!(code: "enterprise-monthly").amount_cny).to eq(4999.00)
    end

    it "marks exactly one plan as default" do
      described_class.seed!
      expect(Billing::Plan.where(is_default: true).count).to eq(1)
    end

    it "marks the free plan as the default" do
      described_class.seed!
      expect(Billing::Plan.find_by!(code: "free").is_default).to be true
    end

    it "creates PlanLimit rows for the free plan" do
      described_class.seed!
      free_plan = Billing::Plan.find_by!(code: "free")
      expect(free_plan.limit_for("page")).to eq(10)
      expect(free_plan.limit_for("entity")).to eq(5)
      expect(free_plan.limit_for("member")).to eq(1)
    end

    it "creates PlanLimit rows for the pro-monthly plan" do
      described_class.seed!
      pro = Billing::Plan.find_by!(code: "pro-monthly")
      expect(pro.limit_for("page")).to eq(500)
      expect(pro.limit_for("entity")).to eq(200)
      expect(pro.limit_for("member")).to eq(25)
    end

    it "sets unlimited (-1) limits for the enterprise plan" do
      described_class.seed!
      enterprise = Billing::Plan.find_by!(code: "enterprise-monthly")
      expect(enterprise.limit_for("page")).to eq(Billing::PlanLimit::UNLIMITED)
      expect(enterprise.limit_for("member")).to eq(Billing::PlanLimit::UNLIMITED)
    end

    it "enables all registered countable items (and no longer flowchart)" do
      described_class.seed!
      enabled_keys = Billing::CountableItem.enabled.pluck(:key)
      expect(enabled_keys).to match_array(Billing::Countable::Registry.keys)
      expect(enabled_keys).to contain_exactly("page", "entity", "member")
      expect(enabled_keys).not_to include("flowchart")
    end

    it "creates paid plans with trial_days > 0" do
      described_class.seed!
      paid_plans = Billing::Plan.where.not(code: "free")
      expect(paid_plans.all? { |p| p.trial_days > 0 }).to be true
    end

    it "creates the free plan with trial_days = 0" do
      described_class.seed!
      expect(Billing::Plan.find_by!(code: "free").trial_days).to eq(0)
    end

    context "idempotency" do
      it "running twice still yields 4 plans (no duplicates)" do
        described_class.seed!
        described_class.seed!
        expect(Billing::Plan.count).to eq(4)
      end

      it "running twice produces no duplicate plan_limits" do
        described_class.seed!
        described_class.seed!
        # Each plan caps the three explicitly-limited items (page, entity, member);
        # other countable items default to unlimited (no PlanLimit row).
        Billing::Plan.all.each do |plan|
          expect(plan.plan_limits.count).to eq(3)
        end
      end

      it "does not create duplicate countable items" do
        described_class.seed!
        described_class.seed!
        keys = Billing::CountableItem.pluck(:key)
        expect(keys.uniq.length).to eq(keys.length)
      end
    end

    context "with an existing plan whose name has been edited" do
      it "preserves explicit catalog edits on re-seed" do
        described_class.seed!
        # The seeder always updates attributes on subsequent runs — this is the
        # intended convergence behaviour (unlike the old find_and_skip approach).
        free_plan = Billing::Plan.find_by!(code: "free")
        free_plan.update_column(:name, "Custom Free Tier")

        described_class.seed!
        expect(free_plan.reload.name).to eq("Custom Free Tier")
      end
    end

    context "when no default plan exists before seeding" do
      it "marks only the free plan as default" do
        described_class.seed!
        expect(Billing::Plan.where(is_default: true).pluck(:code)).to eq(["free"])
      end
    end
  end
end
