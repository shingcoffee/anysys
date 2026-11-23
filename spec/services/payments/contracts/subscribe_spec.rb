require "rails_helper"
require "ostruct"

RSpec.describe Payments::Contracts::Subscribe do
  def form(attrs = {}) = described_class.new(OpenStruct.new).tap { |f| f.validate(attrs) }

  let(:valid_attrs) do
    { external_ref: "s1", plan_name: "Pro", amount: 20.00, cycle: "monthly", provider: "alipay", currency: "cny" }
  end

  it "accepts a valid monthly subscription" do
    expect(form(valid_attrs).errors).to be_empty
  end

  it "rejects missing plan_name" do
    expect(form(valid_attrs.except(:plan_name)).errors[:plan_name]).to be_present
  end

  it "rejects missing or blank currency before persistence" do
    [valid_attrs.except(:currency), valid_attrs.merge(currency: "")].each do |attrs|
      expect(form(attrs).errors[:currency]).to be_present
    end
  end

  it "rejects unknown cycle" do
    expect(form(valid_attrs.merge(cycle: "hourly")).errors[:cycle]).to be_present
  end

  it "rejects zero amount" do
    expect(form(valid_attrs.merge(amount: 0.00, provider: "wechat_pay")).errors[:amount]).to be_present
  end

  it "rejects a non-finite amount" do
    expect(form(valid_attrs.merge(amount: "Infinity")).errors[:amount]).to be_present
  end

  it "rounds zero-decimal currency amounts to whole units" do
    attrs = valid_attrs.merge(amount: "1000.50", currency: "jpy", provider: "stripe")
    contract = form(attrs)
    expect(contract.errors[:amount]).to be_empty
    expect(contract.amount).to eq(1001.00)
  end

  it "rejects unknown provider" do
    expect(form(valid_attrs.merge(provider: "bogus_gateway")).errors[:provider]).to be_present
  end

  it "accepts stripe as a valid provider (registered gateway)" do
    expect(form(valid_attrs.merge(provider: "stripe")).errors[:provider]).to be_blank
  end
end
