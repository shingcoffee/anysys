# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Coupon, type: :model do
  describe "validations" do
    it "requires code, name, discount_type, duration" do
      coupon = described_class.new
      expect(coupon).not_to be_valid
      %i[code name discount_type duration].each do |attr|
        expect(coupon.errors[attr]).to be_present
      end
    end

    it "requires unique code" do
      create(:billing_coupon, code: "SAVE10")
      dup = build(:billing_coupon, code: "SAVE10")
      expect(dup).not_to be_valid
    end

    it "validates discount_type inclusion" do
      expect(build(:billing_coupon, discount_type: "bogus")).not_to be_valid
    end

    it "validates duration inclusion" do
      expect(build(:billing_coupon, duration: "quarterly")).not_to be_valid
    end

    it "validates percent_off (1–100) when type is percent" do
      expect(build(:billing_coupon, discount_type: "percent", percent_off: 0)).not_to be_valid
      expect(build(:billing_coupon, discount_type: "percent", percent_off: 101)).not_to be_valid
      expect(build(:billing_coupon, discount_type: "percent", percent_off: 50)).to be_valid
    end

    it "validates amount_off_cents > 0 when type is fixed" do
      expect(build(:billing_coupon, :fixed, amount_off_cents: 0)).not_to be_valid
      expect(build(:billing_coupon, :fixed, amount_off_cents: 100)).to be_valid
    end

    it "validates duration_in_cycles > 0 when duration is repeating" do
      expect(build(:billing_coupon, :repeating, duration_in_cycles: 0)).not_to be_valid
      expect(build(:billing_coupon, :repeating, duration_in_cycles: 3)).to be_valid
    end
  end

  describe "#redeemable?" do
    it "is true for a basic active coupon" do
      expect(build(:billing_coupon).redeemable?).to be true
    end

    it "is false when inactive" do
      expect(build(:billing_coupon, :inactive).redeemable?).to be false
    end

    it "is false when max_redemptions reached" do
      coupon = build(:billing_coupon, max_redemptions: 5, times_redeemed: 5)
      expect(coupon.redeemable?).to be false
    end

    it "is true when times_redeemed is below max" do
      coupon = build(:billing_coupon, max_redemptions: 5, times_redeemed: 4)
      expect(coupon.redeemable?).to be true
    end

    it "is true when max_redemptions is nil (unlimited)" do
      coupon = build(:billing_coupon, max_redemptions: nil, times_redeemed: 999)
      expect(coupon.redeemable?).to be true
    end

    it "is false when past redeem_by date" do
      expect(build(:billing_coupon, :expired).redeemable?).to be false
    end

    it "is true when redeem_by is nil (no expiry)" do
      coupon = build(:billing_coupon, redeem_by: nil)
      expect(coupon.redeemable?).to be true
    end

    it "is true when redeem_by is in the future" do
      coupon = build(:billing_coupon, redeem_by: 1.day.from_now)
      expect(coupon.redeemable?).to be true
    end
  end

  describe "#usable_on_invoice?" do
    it "is true for an attached coupon whose inventory is already reserved" do
      coupon = build(:billing_coupon, max_redemptions: 1, times_redeemed: 1)
      expect(coupon.redeemable?).to be false
      expect(coupon.usable_on_invoice?).to be true
    end

    it "is false when inactive" do
      expect(build(:billing_coupon, :inactive).usable_on_invoice?).to be false
    end

    it "is false when past redeem_by date" do
      expect(build(:billing_coupon, :expired).usable_on_invoice?).to be false
    end
  end

  describe "#applies_to_currency?" do
    it "is true for percent coupons regardless of currency" do
      expect(build(:billing_coupon).applies_to_currency?("USD")).to be true
      expect(build(:billing_coupon).applies_to_currency?("CNY")).to be true
    end

    it "does not treat a missing fixed currency as unrestricted" do
      coupon = build(:billing_coupon, :fixed, currency: nil)
      expect(coupon.applies_to_currency?("USD")).to be false
    end

    it "is false when a fixed coupon's currency does not match" do
      coupon = build(:billing_coupon, :fixed, currency: "CNY")
      expect(coupon.applies_to_currency?("USD")).to be false
      expect(coupon.applies_to_currency?("CNY")).to be true
    end
  end

  describe "#discount_for" do
    context "percent discount" do
      let(:coupon) { build(:billing_coupon, discount_type: "percent", percent_off: 20) }

      it "returns 20% of the amount" do
        expect(coupon.discount_for(10_000)).to eq(2_000)
      end

      it "floors fractional cents" do
        # 20% of 999 = 199.8 → floors to 199
        expect(coupon.discount_for(999)).to eq(199)
      end

      it "clamps to the full amount if percent would exceed it" do
        coupon100 = build(:billing_coupon, discount_type: "percent", percent_off: 100)
        expect(coupon100.discount_for(5_000)).to eq(5_000)
      end
    end

    context "fixed discount" do
      let(:coupon) { build(:billing_coupon, :fixed, amount_off_cents: 1_500) }

      it "returns the fixed amount" do
        expect(coupon.discount_for(10_000)).to eq(1_500)
      end

      it "clamps to the amount when fixed exceeds it" do
        expect(coupon.discount_for(500)).to eq(500)
      end
    end
  end

  describe "history" do
    it "restricts deletion when a redemption references the coupon" do
      coupon = create(:billing_coupon)
      subscription = create(:billing_subscription)
      Billing::Activities::ApplyCoupon.call(subscription: subscription, coupon: coupon)
      expect(coupon.destroy).to be(false)
      expect(coupon.reload.times_redeemed).to eq(1)
    end
  end
end
