# frozen_string_literal: true

require "rails_helper"

RSpec.describe "utility semantic conformance" do
  def body(klass, config)
    result = CodeGenerators::TestRunner.run(klass, config: config)
    expect(result[:validation_errors]).to be_empty
    result[:body]
  end

  def sample(klass, overrides = {})
    klass.sample_input.merge(overrides)
  end

  describe CodeGenerators::ElementTypes::Process::Utility::BarcodeGenerateGenerator do
    it "does not let hidden includeText change raster emission" do
      %w[png jpg base64].each do |fmt|
        base = sample(described_class, "outputFormat" => fmt)
        expect(body(described_class, base.merge("includeText" => true)))
          .to eq(body(described_class, base.merge("includeText" => false))), "outputFormat=#{fmt} leaked includeText"
      end
    end

    it "does not let the hidden textFont field change emission for raster output" do
      %w[png jpg base64].each do |fmt|
        base = sample(described_class, "outputFormat" => fmt)
        expect(body(described_class, base.merge("textFont" => "Arial")))
          .to eq(body(described_class, base.merge("textFont" => "Helvetica"))), "outputFormat=#{fmt} leaked textFont"
      end
    end

    it "actually renders the human-readable line when includeText is on" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: sample(described_class, "outputFormat" => "svg", "includeText" => true, "textFont" => "Arial"),
        ctx: { sku: "ABC123" }
      )

      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:barcode_image]["bytes"]).to include("<text")
      expect(result[:ctx][:barcode_image]["bytes"]).to include("ABC123")
    end

    it "omits the human-readable line when includeText is off" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: sample(described_class, "outputFormat" => "svg", "includeText" => false),
        ctx: { sku: "ABC123" }
      )

      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:barcode_image]["bytes"]).not_to include("<text")
    end
  end

  describe CodeGenerators::ElementTypes::Process::Utility::GeolocationLookupGenerator do
    it "honors otherVariable" do
      base = sample(described_class, "otherVariable" => "a")
      expect(body(described_class, base.merge("otherVariable" => "a")))
        .not_to eq(body(described_class, base.merge("otherVariable" => "z")))
    end
  end

  describe CodeGenerators::ElementTypes::Process::Utility::CurrencyConvertGenerator do
    it "does not let hidden staticRates change emission for fixed rates" do
      base = sample(described_class, "rateSource" => "fixed")
      expect(body(described_class, base.merge("staticRates" => [{ "key" => "EUR", "value" => "0.5" }])))
        .to eq(body(described_class, base))
    end

    it "honors ratesVariable for ctx-backed rate sources" do
      base = sample(described_class, "rateSource" => "ctx")
      expect(body(described_class, base.merge("ratesVariable" => "rates_a")))
        .not_to eq(body(described_class, base.merge("ratesVariable" => "rates_b")))
    end

    it "honors staticRates for the config rate source" do
      base = sample(described_class, "rateSource" => "config")
      expect(body(described_class, base.merge("staticRates" => [{ "key" => "EUR", "value" => "0.9" }])))
        .not_to eq(body(described_class, base.merge("staticRates" => [{ "key" => "EUR", "value" => "0.5" }])))
    end

    it "converts using the emitted rate table" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: sample(described_class, "rateSource" => "config", "fromCurrency" => "USD", "toCurrency" => "EUR",
                                        "staticRates" => [{ "key" => "EUR", "value" => "0.5" }]),
        ctx: { price: 10.0 }
      )
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:converted]).to eq("5.00")
    end
  end

  describe CodeGenerators::ElementTypes::Process::Utility::AiInferenceGenerator do
    it "carries no streaming vocabulary" do
      source = File.read(Rails.root.join(
        "app/services/code_generators/element_types/process/utility/ai_inference_generator.rb"
      ))
      expect(source.scan(/["']streaming["']/)).to be_empty
    end
  end

  describe CodeGenerators::ElementTypes::Process::Utility::AuditLogGenerator do
    it "ignores a removed alias entirely" do
      base = described_class.sample_input
      expect(body(described_class, base.merge("action" => "other", "targetKey" => "other", "persistTo" => "db")))
        .to eq(body(described_class, base))
    end
  end

  describe CodeGenerators::ElementTypes::Process::Utility::I18nTranslateGenerator do
    it "ignores a removed alias entirely" do
      base = described_class.sample_input
      expect(body(described_class, base.merge("translationKey" => "x", "defaultValue" => "y")))
        .to eq(body(described_class, base))
    end
  end
end
