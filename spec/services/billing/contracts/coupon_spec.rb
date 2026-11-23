# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Contracts::Coupon do
  def contract(attrs = {})
    defaults = {
      code: "SAVE20", name: "Save 20%", discount_type: "percent",
      percent_off: 20, duration: "once"
    }
    model = OpenStruct.new(defaults.merge(attrs))
    described_class.new(model)
  end

  it "is valid with percent discount" do
    expect(contract.valid?).to be true
  end

  it "is valid with fixed discount" do
    c = contract(discount_type: "fixed", percent_off: nil, amount_off_cents: 500, currency: "CNY")
    expect(c.valid?).to be true
  end

  it "requires code" do
    c = contract(code: nil)
    expect(c.valid?).to be false
    expect(c.errors[:code]).to include("can't be blank")
  end

  it "requires name" do
    c = contract(name: nil)
    expect(c.valid?).to be false
    expect(c.errors[:name]).to include("can't be blank")
  end

  it "requires discount_type to be percent or fixed" do
    c = contract(discount_type: "flat")
    expect(c.valid?).to be false
    expect(c.errors[:discount_type]).to be_present
  end

  it "requires percent_off in 1..100 when discount_type is percent" do
    c = contract(discount_type: "percent", percent_off: 0)
    expect(c.valid?).to be false
    expect(c.errors[:percent_off]).to be_present
  end

  it "requires amount_off_cents > 0 when discount_type is fixed" do
    c = contract(discount_type: "fixed", percent_off: nil, amount_off_cents: 0)
    expect(c.valid?).to be false
    expect(c.errors[:amount_off_cents]).to be_present
  end

  it "requires duration_in_cycles when duration is repeating" do
    c = contract(duration: "repeating", duration_in_cycles: nil)
    expect(c.valid?).to be false
    expect(c.errors[:duration_in_cycles]).to be_present
  end

  it "requires max_redemptions > 0 when present" do
    c = contract(max_redemptions: 0)
    expect(c.valid?).to be false
    expect(c.errors[:max_redemptions]).to be_present
  end

  it "accepts max_redemptions nil (unlimited)" do
    c = contract(max_redemptions: nil)
    expect(c.valid?).to be true
  end
end
