# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Contracts::Plan do
  def contract(attrs = {})
    defaults = {
      code: "BASIC", name: "Basic Plan",
      amount_usd: "99.00", amount_cny: "699.00",
      interval: "monthly", trial_days: 0, position: 0
    }
    model = OpenStruct.new(defaults.merge(attrs))
    described_class.new(model)
  end

  it "is valid with all required fields" do
    expect(contract.valid?).to be true
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

  it "requires amount_usd >= 0" do
    c = contract(amount_usd: "-1")
    expect(c.valid?).to be false
    expect(c.errors[:amount_usd]).to be_present
  end

  it "accepts amount_usd == 0 (free plan)" do
    c = contract(amount_usd: "0", amount_cny: "0")
    expect(c.valid?).to be true
  end

  it "requires amount_cny >= 0" do
    c = contract(amount_cny: "-1")
    expect(c.valid?).to be false
    expect(c.errors[:amount_cny]).to be_present
  end

  it "accepts amount_cny == 0 (free plan)" do
    c = contract(amount_cny: "0")
    expect(c.valid?).to be true
  end

  it "requires interval to be monthly or yearly" do
    c = contract(interval: "weekly")
    expect(c.valid?).to be false
    expect(c.errors[:interval]).to be_present
  end

  it "accepts monthly interval" do
    c = contract(interval: "monthly")
    expect(c.valid?).to be true
  end

  it "accepts yearly interval" do
    c = contract(interval: "yearly")
    expect(c.valid?).to be true
  end
end
