# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CurrencyResolver do
  describe ".for_locale" do
    it "returns CNY for zh-CN" do
      expect(described_class.for_locale("zh-CN")).to eq("CNY")
    end

    it "returns CNY for zh" do
      expect(described_class.for_locale("zh")).to eq("CNY")
    end

    it "returns USD for en" do
      expect(described_class.for_locale("en")).to eq("USD")
    end

    it "returns USD for nil (falls through to USD default)" do
      expect(described_class.for_locale(nil)).to eq("USD")
    end

    it "returns USD for an empty string" do
      expect(described_class.for_locale("")).to eq("USD")
    end
  end

  describe ".symbol" do
    it "returns ¥ for CNY" do
      expect(described_class.symbol("CNY")).to eq("¥")
    end

    it "returns $ for USD" do
      expect(described_class.symbol("USD")).to eq("$")
    end

    it "accepts lowercase currency codes" do
      expect(described_class.symbol("cny")).to eq("¥")
      expect(described_class.symbol("usd")).to eq("$")
    end

    it "resolves known ISO currencies via RubyMoney's symbol table" do
      expect(described_class.symbol("EUR")).to eq("€")
      expect(described_class.symbol("GBP")).to eq("£")
    end

    it "falls back to the upcased code itself for currencies RubyMoney does not know" do
      expect(described_class.symbol("zzz")).to eq("ZZZ")
    end
  end

  describe ".format" do
    it "formats CNY cents correctly" do
      expect(described_class.format(99900, "CNY")).to eq("¥999.00")
    end

    it "formats USD cents correctly" do
      expect(described_class.format(2900, "USD")).to eq("$29.00")
    end

    it "handles zero cents" do
      expect(described_class.format(0, "USD")).to eq("$0.00")
    end

    it "handles fractional display" do
      expect(described_class.format(199, "USD")).to eq("$1.99")
    end

    it "omits the minor unit for zero-decimal currencies" do
      expect(described_class.format(1000, "JPY")).to eq("¥1000")
    end

    it "does not insert a thousands separator" do
      expect(described_class.format(123456, "USD")).to eq("$1234.56")
    end

    it "falls back to a 2-decimal format for unknown currencies" do
      expect(described_class.format(2900, "ZZZ")).to eq("ZZZ29.00")
    end
  end

  describe ".format_amount" do
    it "formats a major-unit (dollar) amount" do
      expect(described_class.format_amount(29.5, "USD")).to eq("$29.50")
      expect(described_class.format_amount(999, "CNY")).to eq("¥999.00")
    end

    it "falls back to a 2-decimal format for unknown currencies" do
      expect(described_class.format_amount(29, "ZZZ")).to eq("ZZZ29.00")
    end
  end

  describe ".zero_decimal?" do
    it "is true for currencies with no minor unit" do
      expect(described_class.zero_decimal?("JPY")).to be(true)
      expect(described_class.zero_decimal?("krw")).to be(true)
    end

    it "is false for currencies with a minor unit" do
      expect(described_class.zero_decimal?("USD")).to be(false)
      expect(described_class.zero_decimal?("CNY")).to be(false)
    end

    it "is false for unknown or blank currencies" do
      expect(described_class.zero_decimal?("ZZZ")).to be(false)
      expect(described_class.zero_decimal?("")).to be(false)
    end
  end

  describe ".for_customer" do
    context "when the customer has no locale attribute" do
      let(:customer) { double("Customer") }

      it "falls back to I18n.locale and returns USD when locale is :en" do
        allow(I18n).to receive(:locale).and_return(:en)
        expect(described_class.for_customer(customer)).to eq("USD")
      end

      it "falls back to I18n.locale and returns CNY when locale is :'zh-CN'" do
        allow(I18n).to receive(:locale).and_return(:"zh-CN")
        expect(described_class.for_customer(customer)).to eq("CNY")
      end
    end

    context "when the customer has a locale attribute that is blank" do
      let(:customer) { double("Customer", locale: nil) }

      it "falls back to I18n.locale" do
        allow(I18n).to receive(:locale).and_return(:en)
        expect(described_class.for_customer(customer)).to eq("USD")
      end
    end

    context "when the customer has a non-blank locale attribute" do
      it "uses the customer locale for zh-CN" do
        customer = double("Customer", locale: "zh-CN")
        expect(described_class.for_customer(customer)).to eq("CNY")
      end

      it "uses the customer locale for en" do
        customer = double("Customer", locale: "en")
        expect(described_class.for_customer(customer)).to eq("USD")
      end
    end
  end
end
