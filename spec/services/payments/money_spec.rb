# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Money do
  describe "#smallest_unit (Stripe amount)" do
    it "returns cents for a 2-decimal currency" do
      expect(described_class.new(5.00, "usd").smallest_unit).to eq(500)
    end

    it "returns whole units for a zero-decimal currency" do
      expect(described_class.new(1000.00, "jpy").smallest_unit).to eq(1000)
    end
  end

  describe "#decimal_string (Alipay/PayPal amount value)" do
    it "formats a 2-decimal currency as a fixed-2 string" do
      expect(described_class.new(12.34, "cny").decimal_string).to eq("12.34")
    end

    it "formats a zero-decimal currency with no decimal places" do
      expect(described_class.new(1000.00, "jpy").decimal_string).to eq("1000")
    end
  end

  describe ".from_major" do
    it "parses a major-unit string into a Money object" do
      money = described_class.from_major("12.34", "usd")
      expect(money.amount).to eq(12.34)
      expect(money.smallest_unit).to eq(1234)
    end

    it "parses a zero-decimal major-unit string" do
      money = described_class.from_major("1000", "jpy")
      expect(money.amount).to eq(1000.00)
      expect(money.smallest_unit).to eq(1000)
    end

    it "returns nil for a blank value" do
      expect(described_class.from_major(nil, "usd")).to be_nil
      expect(described_class.from_major("", "usd")).to be_nil
    end
  end

  describe ".from_smallest_unit" do
    it "returns a Money object for a 2-decimal currency" do
      money = described_class.from_smallest_unit(1234, "USD")
      expect(money.amount).to eq(12.34)
    end

    it "returns a Money object for a zero-decimal currency" do
      money = described_class.from_smallest_unit(1000, "JPY")
      expect(money.amount).to eq(1000.00)
    end

    it "round-trips with #smallest_unit" do
      money = described_class.new(1000.00, "jpy")
      expect(described_class.from_smallest_unit(money.smallest_unit, "jpy").amount).to eq(1000.00)
    end

    it "returns nil for nil" do
      expect(described_class.from_smallest_unit(nil, "JPY")).to be_nil
    end
  end

  describe ".to_iso_minor_units (Billing::CurrencyResolver.format input)" do
    it "converts major units to minor units for a 2-decimal currency" do
      expect(described_class.to_iso_minor_units(100.00, "CNY")).to eq(10_000)
    end

    it "converts major units to whole units for a zero-decimal currency" do
      expect(described_class.to_iso_minor_units(100.00, "JPY")).to eq(100)
    end
  end

  describe ".normalize" do
    it "rounds standard currencies half-up to two decimal places" do
      expect(described_class.normalize("31.095", "USD")).to eq(31.10)
    end

    it "rounds zero-decimal currencies half-up to whole units" do
      expect(described_class.normalize("1000.50", "JPY")).to eq(1001.00)
    end

    it "rejects non-finite and unparseable amounts" do
      expect { described_class.normalize("NaN", "USD") }.to raise_error(ArgumentError)
      expect { described_class.normalize("Infinity", "USD") }.to raise_error(ArgumentError)
      expect { described_class.normalize(["1.00"], "USD") }.to raise_error(ArgumentError)
    end
  end
end
