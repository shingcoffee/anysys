# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::DateTimeCalcGenerator do
  let(:context) { {} }
  let(:base) { { "operation" => "now", "resultVar" => "datetime" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"date_time_calc.failed", FlowchartRuntime::Dates::Error) do
          ctx[:datetime] = FlowchartRuntime::Dates.apply(nil, operation: "now")
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

  def codes(config)
    generate(config).validate_config(config).map { |error| error.respond_to?(:code) ? error.code : error }
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  def variant(operation, extra = {})
    described_class.sample_input.merge("operation" => operation, "resultVar" => "datetime").merge(extra)
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(generate(sample).validate_config(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(generate(sample).generate_step_method) }.not_to raise_error
    lint!(sample)
  end

  {
    "now" => {},
    "add" => { "sourceVariable" => "start_date", "amount" => 1, "unit" => "days" },
    "subtract" => { "sourceVariable" => "start_date", "amount" => 1, "unit" => "days" },
    "difference" => { "sourceVariable" => "start_date", "endVariable" => "end_date", "unit" => "days" },
    "start_of" => { "sourceVariable" => "start_date", "unit" => "days" },
    "end_of" => { "sourceVariable" => "start_date", "unit" => "days" },
    "age" => { "sourceVariable" => "start_date" },
    "compare" => { "sourceVariable" => "start_date", "endVariable" => "end_date" },
    "format" => { "sourceVariable" => "start_date", "formatString" => "%Y-%m-%d" },
    "parse" => { "sourceVariable" => "start_date" },
    "convert_timezone" => { "sourceVariable" => "start_date", "targetTimezone" => "UTC" }
  }.each do |operation, extra|
    it "emits a BodyLint-clean body for operation #{operation}" do
      config = variant(operation, extra)
      expect(generate(config).validate_config(config)).to eq([])
      expect(body(config)).to include("FlowchartRuntime::Dates.apply")
      expect(body(config)).to include(%(operation: "#{operation}"))
      lint!(config)
    end
  end

  it "writes now at runtime" do
    travel_to Time.utc(2026, 4, 19, 12, 30) do
      Time.use_zone("UTC") do
        result = execute(base.merge("outputFormat" => "iso8601"), {})
        expect(result[:outcome]).to be(true)
        expect(result[:ctx][:datetime]).to eq("2026-04-19T12:30:00Z")
      end
    end
  end

  it "adds days at runtime" do
    result = execute(
      variant("add", "sourceVariable" => "start_date", "amount" => 2, "unit" => "days"),
      { start_date: Time.utc(2026, 4, 19) }
    )
    expect(result[:ctx][:datetime].to_date).to eq(Date.new(2026, 4, 21))
  end

  it "converts timezones at runtime" do
    result = execute(
      variant("convert_timezone", "sourceVariable" => "start_date", "sourceTimezone" => "UTC",
                                  "targetTimezone" => "America/New_York", "outputFormat" => "iso8601"),
      { start_date: "2026-04-19 12:00:00" }
    )
    expect(result[:ctx][:datetime]).to include("2026-04-19T08:00:00")
  end

  it "rejects an invalid outputFormat" do
    expect(codes(base.merge("outputFormat" => "garbage"))).to include(:invalid_format)
  end

  it "omits amount for now and emits it for add" do
    expect(body(base)).not_to include("amount:")
    add = variant("add", "sourceVariable" => "start_date", "amount" => 3, "unit" => "days")
    expect(body(add)).to include("amount: 3")
  end

  it "computes start_of, age, and compare at runtime" do
    stamp = Time.utc(2026, 4, 19, 15, 30)
    start_of = execute(variant("start_of", "sourceVariable" => "start_date", "unit" => "days"), { start_date: stamp })
    expect(start_of[:ctx][:datetime]).to eq(stamp.beginning_of_day)

    travel_to Time.utc(2026, 4, 19) do
      age = execute(variant("age", "sourceVariable" => "start_date"), { start_date: Date.new(2000, 4, 19) })
      expect(age[:ctx][:datetime]).to eq(26)
    end

    compared = execute(
      variant("compare", "sourceVariable" => "start_date", "endVariable" => "end_date"),
      { start_date: Time.utc(2026, 4, 19), end_date: Time.utc(2026, 4, 20) }
    )
    expect(compared[:ctx][:datetime]).to eq(-1)
  end

  it "rejects an invalid timezone" do
    expect(codes(base.merge("timezoneAware" => true, "timezone" => "Bogus/Zone"))).to include(:invalid_timezone)
  end
end
