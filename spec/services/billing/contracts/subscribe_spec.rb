# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Contracts::Subscribe do
  let(:active_plan)    { create(:billing_plan, active: true) }
  let(:inactive_plan)  { create(:billing_plan, :inactive) }
  let(:redeemable_coupon) { create(:billing_coupon) }
  let(:exhausted_coupon)  { create(:billing_coupon, :exhausted) }

  def contract(attrs = {})
    model = OpenStruct.new({ request_key: SecureRandom.uuid, currency: "USD" }.merge(attrs))
    described_class.new(model)
  end

  describe "plan_code" do
    it "is required" do
      c = contract(plan_code: nil, coupon_code: nil)
      expect(c.valid?).to be false
      expect(c.errors[:plan_code]).to include("can't be blank")
    end

    it "is invalid when plan is inactive" do
      c = contract(plan_code: inactive_plan.code, coupon_code: nil)
      expect(c.valid?).to be false
      expect(c.errors[:plan_code]).to include("must resolve to an active plan")
    end

    it "is invalid when plan does not exist" do
      c = contract(plan_code: "NONEXISTENT", coupon_code: nil)
      expect(c.valid?).to be false
      expect(c.errors[:plan_code]).to include("must resolve to an active plan")
    end

    it "is valid for an active plan code" do
      c = contract(plan_code: active_plan.code, coupon_code: nil)
      expect(c.valid?).to be true
    end
  end

  describe "coupon_code" do
    it "is valid when absent" do
      c = contract(plan_code: active_plan.code, coupon_code: nil)
      expect(c.valid?).to be true
    end

    it "is valid when present and redeemable" do
      c = contract(plan_code: active_plan.code, coupon_code: redeemable_coupon.code)
      expect(c.valid?).to be true
    end

    it "is invalid when coupon does not exist" do
      c = contract(plan_code: active_plan.code, coupon_code: "BADCODE")
      expect(c.valid?).to be false
      expect(c.errors[:coupon_code]).to include("not found")
    end

    it "is invalid when coupon is not redeemable" do
      c = contract(plan_code: active_plan.code, coupon_code: exhausted_coupon.code)
      expect(c.valid?).to be false
      expect(c.errors[:coupon_code]).to include("is not redeemable")
    end

    it "is invalid when a fixed coupon is denominated in another currency" do
      coupon = create(:billing_coupon, :fixed, currency: "CNY")
      c = contract(plan_code: active_plan.code, coupon_code: coupon.code, currency: "USD")
      expect(c.valid?).to be false
      expect(c.errors[:coupon_code]).to include("does not apply to this currency")
    end
  end
end
