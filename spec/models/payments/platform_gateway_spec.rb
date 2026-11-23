# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::PlatformGateway do
  describe ".for_provider" do
    it "creates an unavailable row on first access" do
      gw = described_class.for_provider("stripe")
      expect(gw.provider).to eq("stripe")
      expect(gw.available).to be(false)
    end

    it "returns the same row on subsequent access" do
      first  = described_class.for_provider("alipay")
      second = described_class.for_provider("alipay")
      expect(second.id).to eq(first.id)
    end

    it "accepts a symbol provider key" do
      gw = described_class.for_provider(:wechat_pay)
      expect(gw.provider).to eq("wechat_pay")
    end
  end

  describe ".available_providers" do
    it "returns only available provider keys" do
      described_class.for_provider("alipay").update!(available: true)
      described_class.for_provider("stripe")
      expect(described_class.available_providers).to include("alipay")
      expect(described_class.available_providers).not_to include("stripe")
    end

    it "returns an empty array when none are available" do
      described_class.for_provider("stripe")
      expect(described_class.available_providers).not_to include("stripe")
    end
  end

  describe ".available?" do
    it "returns false for a newly created row" do
      expect(described_class.available?("paypal")).to be(false)
    end

    it "returns true after marking a provider available" do
      described_class.for_provider("alipay").update!(available: true)
      expect(described_class.available?("alipay")).to be(true)
    end
  end

  describe "validations" do
    it "requires a provider" do
      gw = described_class.new(available: false)
      expect(gw).not_to be_valid
      expect(gw.errors[:provider]).to be_present
    end

    it "enforces provider uniqueness" do
      described_class.for_provider("stripe")
      duplicate = described_class.new(provider: "stripe", available: false)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:provider]).to be_present
    end
  end
end
