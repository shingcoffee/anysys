# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::NextSequenceNumberGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"next_sequence_number.failed",
          FlowchartRuntime::Sequence::Error
        ) do
          ctx[:sequence_number] = FlowchartRuntime::Sequence.next(ctx, name: "order", period: "never")
        end
      end
    RUBY
  end

  it "is version 1.2.0" do
    expect(described_class._metadata[:version]).to eq("1.2.0")
  end

  described_class::PERIODS.each do |period|
    it "emits a BodyLint-clean body for resetEvery #{period}" do
      config = described_class.sample_input.merge("resetEvery" => period)
      src = generate(config)
      expect(src).to include("FlowchartRuntime::Sequence.next")
      expect(src).to include("period: \"#{period}\"")
      result = CodeGenerators::BodyLint.check(src, outputs: %w[sequence_number])
      expect(result.ok?).to be(true), "#{result.violations.inspect}\n#{src}"
    end
  end

  it "emits suffix, startAt, step, dateSegment and separator only when they differ from defaults" do
    sample = described_class.sample_input
    expect(generate).not_to include("suffix:")
    expect(generate).not_to include("start_at:")
    expect(generate).not_to include("step:")
    expect(generate).not_to include("date_segment:")
    expect(generate(sample.merge("suffix" => "-CN"))).to include('suffix: "-CN"')
    expect(generate(sample.merge("startAt" => 100))).to include("start_at: 100")
    expect(generate(sample.merge("step" => 5))).to include("step: 5")
    expect(generate(sample.merge("dateSegment" => "year"))).to include('date_segment: "year"')
    expect(generate(sample.merge("dateSegment" => "year", "separator" => "/"))).to include('separator: "/"')
    expect(generate(sample.merge("dateSegment" => "year"))).not_to eq(generate(sample.merge("dateSegment" => "date")))
  end

  it "rejects a non-identifier sequence name" do
    expect(errors(described_class.sample_input.merge("sequenceName" => "order-number")).map(&:code))
      .to include(:invalid_identifier)
  end

  it "keeps English and zh-CN tables_new locale keys in parity" do
    en = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_tables_new.en.yml")).fetch("en")
    zh = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_tables_new.zh-CN.yml")).fetch("zh-CN")
    flatten = lambda do |hash, prefix = ""|
      hash.each_with_object([]) do |(key, value), keys|
        path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        value.is_a?(Hash) ? keys.concat(flatten.call(value, path)) : keys << path
      end
    end
    expect(flatten.call(en)).to match_array(flatten.call(zh))
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    it "writes a formatted sequence number into the result variable" do
      ctx = { customer_id: customer.id, errors: [] }
      config = described_class.sample_input.merge("prefix" => "INV-", "padding" => 6)
      result = execute(config, ctx)
      expect(result[:validation_errors]).to eq([])
      expect(result[:outcome]).to eq("INV-000001")
      expect(ctx[:sequence_number]).to eq("INV-000001")
    end

    it "applies startAt, step, suffix and a year date segment" do
      travel_to Time.zone.local(2026, 11, 16, 12) do
        ctx = { customer_id: customer.id, errors: [] }
        config = described_class.sample_input.merge(
          "prefix" => "INV-",
          "suffix" => "-CN",
          "padding" => 6,
          "startAt" => 100,
          "step" => 5,
          "dateSegment" => "year"
        )
        first = execute(config, ctx)
        expect(first[:outcome]).to eq("INV-2026-000100-CN")
        second = execute(config, { customer_id: customer.id, errors: [] })
        expect(second[:outcome]).to eq("INV-2026-000105-CN")
      end
    end

    it "keeps another tenant's counter of the same name independent" do
      config = described_class.sample_input.merge("prefix" => "", "padding" => 3)
      execute(config, { customer_id: customer.id, errors: [] })
      other_ctx = { customer_id: other.id, errors: [] }
      result = execute(config, other_ctx)
      expect(result[:outcome]).to eq("001")
    end
  end
end
