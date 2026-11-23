# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::OneTimeProviders do
  before { allow(Billing::Onboarding).to receive(:call) }

  def gateways
    [Payments::Gateways::Stripe, Payments::Gateways::Paypal, Payments::Gateways::Alipay, Payments::Gateways::WechatPay]
  end

  it "lists platform one-time gateways that accept the requested currency" do
    platform = ensure_platform_customer
    allow(Payments::EligibleGateways).to receive(:for).with(platform, currency: "USD")
      .and_return([Payments::Gateways::Stripe, Payments::Gateways::Paypal])
    allow(Payments::EligibleGateways).to receive(:for).with(platform, currency: "CNY")
      .and_return([Payments::Gateways::Stripe, Payments::Gateways::Alipay, Payments::Gateways::WechatPay])

    usd = described_class.call(currency: "USD").map { |entry| entry[:key] }
    cny = described_class.call(currency: "CNY").map { |entry| entry[:key] }
    expect(usd).to eq(%w[stripe paypal])
    expect(cny).to eq(%w[stripe alipay wechat_pay])
    expect(described_class.call(currency: "EUR")).to eq([])
  end

  it "keeps incompatible one-time gateways visible but disabled for USD and CNY" do
    platform = ensure_platform_customer
    allow(Payments::EligibleGateways).to receive(:for).with(platform, currency: nil).and_return(gateways)

    usd = described_class.options(currency: "USD").index_by { |entry| entry[:key] }
    expect(usd.fetch("stripe")).to include(enabled: true, currency_compatible: true, reason_key: nil)
    expect(usd.fetch("paypal")).to include(enabled: true, currency_compatible: true, reason_key: nil)
    expect(usd.fetch("alipay")).to include(enabled: false, currency_compatible: false,
      reason_key: "settings_billing.payment_methods.currency_incompatible")
    expect(usd.fetch("wechat_pay")).to include(enabled: false)

    cny = described_class.options(currency: "CNY").index_by { |entry| entry[:key] }
    expect(cny.fetch("alipay")).to include(enabled: true, currency_compatible: true, reason_key: nil)
    expect(cny.fetch("paypal")).to include(enabled: false, currency_compatible: false,
      reason_key: "settings_billing.payment_methods.currency_incompatible")
    expect(described_class.options(currency: "EUR")).to eq([])
  end

  it "returns nothing when the platform owner customer is missing" do
    allow(Customer).to receive(:find_by).with(id: Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID).and_return(nil)
    expect(described_class.call(currency: "USD")).to eq([])
    expect(described_class.options(currency: "USD")).to eq([])
  end
end
