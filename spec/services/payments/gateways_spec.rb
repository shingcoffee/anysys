# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Gateways do
  describe ".for" do
    it "resolves a registered gateway by key (string or symbol)" do
      expect(described_class.for("stripe")).to eq(Payments::Gateways::Stripe)
      expect(described_class.for(:alipay)).to eq(Payments::Gateways::Alipay)
    end

    it "raises ArgumentError for an unknown gateway key" do
      expect { described_class.for("does_not_exist") }
        .to raise_error(ArgumentError, /unknown payment gateway/)
    end
  end

  describe ".keys / .all" do
    it "exposes every registered gateway" do
      expect(described_class.keys).to include(:alipay, :wechat_pay, :stripe, :paypal)
      expect(described_class.all).to include(
        Payments::Gateways::Alipay, Payments::Gateways::WechatPay,
        Payments::Gateways::Stripe, Payments::Gateways::Paypal
      )
    end
  end
end
