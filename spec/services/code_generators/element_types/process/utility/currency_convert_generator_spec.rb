# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::CurrencyConvertGenerator do
  let(:element) { { "config" => described_class.sample_input } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {})
  end

  def body(config = described_class.sample_input)
    generate(config).generate_body
  end

  def errors(config)
    generate(config).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only required errors on schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(generate(sample).generate_step_method) }.not_to raise_error
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[converted])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"currency_convert.failed",
          FlowchartRuntime::Currency::Error
        ) do
          converted = FlowchartRuntime::Currency.convert(
            ctx,
            amount: ctx[:price],
            from: "USD",
            to: "EUR",
            rate_source: "fixed",
            fixed_rate: 0.92
          )
          ctx[:converted] = converted
          true
        end
      end
    RUBY
  end

  it "generates a static-rate table step" do
    expect(generated_step(described_class.sample_input.merge(
      "rateSource" => "config",
      "staticRates" => [{ "key" => "EUR", "value" => "0.5" }]
    ))).to include('rate_source: "config"', '"EUR" => "0.5"')
  end

  it "does not offer an external rate URL" do
    names = described_class._config_schema.fields.map(&:name)
    expect(names).not_to include("rateApiUrl", "cacheRates")
    expect(described_class::RATE_SOURCES).to eq(%w[fixed ctx config])
  end

  described_class::RATE_SOURCES.each do |source|
    it "emits a BodyLint-clean body for rateSource #{source}" do
      config = described_class.sample_input.merge("rateSource" => source)
      config["fixedRate"] = 0.92 if source == "fixed"
      config["staticRates"] = [{ "key" => "EUR", "value" => "0.9" }] if source == "config"
      next unless errors(config).empty?

      expect(body(config)).to include("FlowchartRuntime::Currency.convert")
      expect(body(config)).not_to include("OutboundHttp")
      expect(CodeGenerators::BodyLint.check(body(config), outputs: %w[converted]).ok?).to be(true)
    end
  end

  it "rejects a non-ISO currency code" do
    expect(errors(described_class.sample_input.merge("fromCurrency" => "dollar")).map(&:code))
      .to include(:invalid_currency)
  end

  describe "behaviour" do
    it "uses currency codes from context when override inputs are set" do
      config = described_class.sample_input.merge("fromCurrencyFrom" => "src", "toCurrencyFrom" => "dst", "fixedRate" => 2)
      expect(body(config)).to include("from: ctx[:src]")
      expect(body(config)).to include("to: ctx[:dst]")
      result = execute(config, { price: 10, src: "USD", dst: "EUR" })
      expect(result[:ctx][:converted]).to eq("20.00")
    end

    it "returns the original amount when onMissingRate is identity" do
      result = execute(
        described_class.sample_input.merge(
          "rateSource" => "config",
          "staticRates" => [{ "key" => "GBP", "value" => "0.5" }],
          "onMissingRate" => "identity"
        ),
        { price: 10 }
      )
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:converted]).to eq("10.00")
    end

    it "converts with a fixed rate" do
      result = execute(described_class.sample_input, { price: 10 })
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:converted]).to eq("9.20")
    end

    it "converts with a static rate table" do
      result = execute(
        described_class.sample_input.merge(
          "rateSource" => "config",
          "staticRates" => [{ "key" => "EUR", "value" => "0.5" }]
        ),
        { price: 10 }
      )
      expect(result[:ctx][:converted]).to eq("5.00")
    end

    it "converts with a ctx rate table" do
      result = execute(
        described_class.sample_input.merge("rateSource" => "ctx", "ratesVariable" => "exchange_rates"),
        { price: 10, exchange_rates: { "EUR" => "0.8" } }
      )
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:converted]).to eq("8.00")
    end
  end
end
