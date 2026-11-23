# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::AvailableProviders do
  before { allow(Billing::Onboarding).to receive(:call) }

  it "offers implemented recurring tokenized Stripe as well as CNY Alipay" do
    platform = ensure_platform_customer
    customer = create(:customer)
    allow(Payments::EligibleGateways).to receive(:for).with(platform, currency: "CNY").and_return([Payments::Gateways::Stripe, Payments::Gateways::Alipay, Payments::Gateways::WechatPay])
    expect(described_class.call(customer: customer, currency: "CNY").map { |entry| entry[:key] }).to eq(%w[stripe alipay])
  end

  it "delegates currency and platform/account availability to EligibleGateways" do
    platform = ensure_platform_customer
    customer = create(:customer)
    expect(Payments::EligibleGateways).to receive(:for).with(platform, currency: "USD").and_return([Payments::Gateways::Stripe])
    expect(described_class.call(customer: customer, currency: "USD").sole).to include(key: "stripe", setup_kind: :stripe_setup)
    expect(described_class.call(customer: customer, currency: "EUR")).to eq([])
  end

  it "does not offer monthly Alipay authorization to a CNY yearly subscription" do
    platform = ensure_platform_customer
    customer = create(:customer)
    create(:billing_subscription, :yearly, customer: customer, currency: "CNY")
    allow(Payments::EligibleGateways).to receive(:for).with(platform, currency: "CNY").and_return([Payments::Gateways::Stripe, Payments::Gateways::Alipay])
    expect(described_class.call(customer: customer, currency: "CNY").map { |option| option[:key] }).to eq(["stripe"])
  end
end
