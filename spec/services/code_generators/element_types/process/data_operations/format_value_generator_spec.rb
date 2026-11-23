# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::FormatValueGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "amount", "formatType" => "number", "resultVar" => "formatted" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"format_value.failed",
          FlowchartRuntime::Formatter::Error
        ) do
          ctx[:formatted] = FlowchartRuntime::Formatter.apply(
            ctx[:amount],
            ctx: ctx,
            format_type: "number"
          )
          true
        end
      end
    RUBY
  end

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def errors(config)
    generate(config).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(body(sample)) }.not_to raise_error
    lint!(sample)
  end

  described_class::FORMAT_TYPES.each do |type|
    it "emits a BodyLint-clean body for formatType #{type}" do
      extra = type == "date" || type == "datetime" ? { "dateStyle" => "iso8601" } : {}
      extra["customFormat"] = "%Y-%m-%d" if extra["dateStyle"] == "custom"
      config = described_class.sample_input.merge("formatType" => type).merge(extra)
      expect(errors(config)).to eq([])
      expect(body(config)).to include(%(format_type: "#{type}"))
      expect(body(config)).to include("FlowchartRuntime::Formatter.apply")
      lint!(config)
    end
  end

  it "emits distinct source for every formatType, phoneStyle and dateStyle" do
    types = described_class::FORMAT_TYPES.map { |type| body(base.merge("formatType" => type)) }
    expect(types.uniq.size).to eq(described_class::FORMAT_TYPES.size)
    styles = described_class::PHONE_STYLES.map { |style| body(base.merge("formatType" => "phone", "phoneStyle" => style)) }
    expect(styles.uniq.size).to eq(described_class::PHONE_STYLES.size)
    dates = described_class::DATE_STYLES.map { |style| body(base.merge("formatType" => "date", "dateStyle" => style, "customFormat" => "%Y-%m-%d")) }
    expect(dates.uniq.size).to eq(described_class::DATE_STYLES.size)
  end

  describe "behaviour" do
    around { |example| I18n.with_locale(:en) { example.run } }

    it "formats each formatType with a concrete source" do
      fixtures = {
        "number" => [1234.5, "1,234.50"],
        "currency" => [12.5, nil],
        "percentage" => [0.5, nil],
        "delimited" => [1234, "1,234"],
        "human_size" => [1024, /KB/],
        "human_number" => [1_500_000, /Million|million/],
        "phone" => ["+14155552671", "+14155552671"],
        "date" => [Date.new(2026, 1, 15), nil],
        "datetime" => [Time.utc(2026, 1, 15, 12), nil]
      }
      fixtures.each do |type, (value, expected)|
        ctx = { amount: value, locale: "en" }
        extra = {}
        extra["phoneStyle"] = "e164" if type == "phone"
        extra["dateStyle"] = "iso8601" if %w[date datetime].include?(type)
        extra["timezone"] = "UTC" if type == "datetime"
        result = execute(base.merge("formatType" => type).merge(extra), ctx)
        expect(result[:outcome]).to be_truthy, type
        if expected.is_a?(Regexp)
          expect(ctx[:formatted]).to match(expected)
        elsif expected
          expect(ctx[:formatted]).to eq(expected)
        else
          expect(ctx[:formatted].to_s).not_to be_empty
        end
      end
    end

    it "formats each phoneStyle and dateStyle" do
      described_class::PHONE_STYLES.each do |style|
        ctx = { amount: "+14155552671" }
        execute(base.merge("formatType" => "phone", "phoneStyle" => style), ctx)
        expect(ctx[:formatted].to_s).to include("415")
      end
      described_class::DATE_STYLES.each do |style|
        ctx = { amount: Date.new(2026, 1, 15) }
        extra = { "formatType" => "date", "dateStyle" => style }
        extra["customFormat"] = "%d/%m/%Y" if style == "custom"
        execute(base.merge(extra), ctx)
        expect(ctx[:formatted].to_s).to match(/2026|15/)
      end
    end

    it "writes fallbackValue when the source is nil" do
      ctx = { amount: nil }
      result = execute(base.merge("fallbackValue" => "n/a"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:formatted]).to eq("n/a")
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable" do
      expect(errors({}).map(&:field)).to include("sourceVariable")
    end

    it "rejects an unknown timezone and phone country" do
      expect(errors(base.merge("formatType" => "datetime", "timezone" => "Bogus/Zone")).map(&:code))
        .to include(:invalid_timezone)
      expect(errors(base.merge("formatType" => "phone", "phoneCountry" => "USA")).map(&:code))
        .to include(:invalid_phone_country)
    end
  end
end
