# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Payments::Contracts::Charge do
  def form(attrs = {}) = described_class.new(OpenStruct.new).tap { |f| f.validate(attrs) }

  let(:valid_attrs) do
    { external_ref: "o1", amount: 1.00, currency: "cny", subject: "s", provider: "wechat_pay" }
  end

  it "accepts a valid cny charge" do
    expect(form(valid_attrs).errors).to be_empty
  end

  it "rejects missing external_ref" do
    expect(form(valid_attrs.except(:external_ref)).errors[:external_ref]).to be_present
  end

  it "rejects a currency unsupported by the gateway" do
    expect(form(valid_attrs.merge(currency: "usd", provider: "alipay")).errors[:currency]).to be_present
  end

  it "accepts a currency the gateway supports (validate returns true)" do
    result = described_class.new(OpenStruct.new).validate(
      valid_attrs.merge(external_ref: "r1", provider: "alipay")
    )
    expect(result).to be(true)
  end

  it "rejects zero or negative amount" do
    expect(form(valid_attrs.merge(amount: 0.00, provider: "alipay")).errors[:amount]).to be_present
  end

  it "rounds amounts to two decimal places" do
    contract = form(valid_attrs.merge(amount: "31.095"))
    expect(contract.errors[:amount]).to be_empty
    expect(contract.amount).to eq(31.10)
  end

  it "rounds zero-decimal currency amounts to whole units" do
    attrs = valid_attrs.merge(amount: "1000.50", currency: "jpy", provider: "stripe")
    contract = form(attrs)
    expect(contract.errors[:amount]).to be_empty
    expect(contract.amount).to eq(1001.00)
  end

  it "rejects unknown provider" do
    expect(form(valid_attrs.merge(provider: "unknown_gw")).errors[:provider]).to be_present
  end
end
