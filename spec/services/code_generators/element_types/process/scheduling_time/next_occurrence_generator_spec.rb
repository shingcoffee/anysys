# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::SchedulingTime::NextOccurrenceGenerator do
  let(:context) { {} }
  let(:base) { { "frequency" => "monthly", "resultVar" => "next_occurrence" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

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

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"next_occurrence.failed",
          FlowchartRuntime::Recurrence::Error
        ) do
          result = FlowchartRuntime::Recurrence.next_occurrences(
            frequency: "monthly",
            start_at: ctx[:series_start],
            from: ctx[:after_time]
          )
          if result[:error]
            return FlowchartRuntime::Step.fail(ctx, :"next_occurrence.\#{result[:error]}")
          end
          ctx[:next_occurrence] = result[:value]
          true
        end
      end
    RUBY
  end

  it "generates a cron step" do
    expect(generated_step(described_class.sample_input.merge("frequency" => "cron", "cronExpression" => "0 9 * * *")))
      .to include('frequency: "cron"', 'cron_expression: "0 9 * * *"')
  end

  described_class::FREQUENCIES.each do |frequency|
    it "emits a BodyLint-clean body for frequency #{frequency}" do
      extra = frequency == "cron" ? { "cronExpression" => "0 9 * * *" } : {}
      config = described_class.sample_input.merge("frequency" => frequency).merge(extra)
      expect(errors(config)).to eq([])
      expect(body(config)).to include(%(frequency: "#{frequency}"))
      expect(body(config)).to include("FlowchartRuntime::Recurrence.next_occurrences")
      lint!(config)
    end
  end

  it "emits distinct source for frequency, monthEndPolicy, businessDayAdjust and returns" do
    freqs = described_class::FREQUENCIES.map { |item| body(base.merge("frequency" => item, "cronExpression" => "0 9 * * *")) }
    expect(freqs.uniq.size).to eq(described_class::FREQUENCIES.size)
    policies = described_class::MONTH_END_POLICIES.map { |item| body(base.merge("monthEndPolicy" => item)) }
    expect(policies.uniq.size).to eq(described_class::MONTH_END_POLICIES.size)
    adjusts = described_class::BUSINESS_ADJUSTS.map { |item| body(base.merge("businessDayAdjust" => item)) }
    expect(adjusts.uniq.size).to eq(described_class::BUSINESS_ADJUSTS.size)
    returns = described_class::RETURNS.map { |item| body(base.merge("returns" => item)) }
    expect(returns.uniq.size).to eq(described_class::RETURNS.size)
  end

  describe "behaviour" do
    around { |example| Time.use_zone("UTC") { example.run } }

    let(:origin) { Time.utc(2026, 1, 15, 12) }

    def run_from(config, extras = {})
      ctx = { series_start: origin, after_time: origin }.merge(extras)
      result = execute(
        described_class.sample_input.merge("startVariable" => "series_start", "fromVariable" => "after_time").merge(config),
        ctx
      )
      [result, ctx]
    end

    it "computes the next occurrence for every frequency" do
      travel_to origin do
        _result, ctx = run_from("frequency" => "monthly")
        expect(ctx[:next_occurrence]).to eq(Time.utc(2026, 2, 15, 12))

        _result, ctx = run_from("frequency" => "daily")
        expect(ctx[:next_occurrence]).to eq(Time.utc(2026, 1, 16, 12))

        _result, ctx = run_from("frequency" => "weekly")
        expect(ctx[:next_occurrence]).to eq(Time.utc(2026, 1, 22, 12))

        _result, ctx = run_from("frequency" => "yearly")
        expect(ctx[:next_occurrence]).to eq(Time.utc(2027, 1, 15, 12))

        _result, ctx = run_from("frequency" => "cron", "cronExpression" => "0 9 * * *")
        expect(ctx[:next_occurrence]).to eq(Time.utc(2026, 1, 16, 9))
      end
    end

    it "returns a list, clamps month end, and shifts to the next business day" do
      _result, ctx = run_from("frequency" => "daily", "returns" => "list", "count" => 2)
      expect(ctx[:next_occurrence].map(&:to_date)).to eq([Date.new(2026, 1, 16), Date.new(2026, 1, 17)])

      jan31 = Time.utc(2026, 1, 31, 12)
      _result, ctx = run_from(
        { "frequency" => "monthly", "dayOfMonth" => 31, "monthEndPolicy" => "clamp" },
        series_start: jan31, after_time: jan31
      )
      expect(ctx[:next_occurrence].to_date).to eq(Date.new(2026, 2, 28))

      friday = Time.utc(2026, 1, 16, 12)
      _result, ctx = run_from(
        { "frequency" => "daily", "businessDayAdjust" => "next_business_day" },
        series_start: friday, after_time: friday
      )
      expect(ctx[:next_occurrence].to_date).to eq(Date.new(2026, 1, 19))

      saturday = Time.utc(2026, 1, 10, 12)
      _result, ctx = run_from(
        { "frequency" => "weekly", "weekdays" => %w[sat], "businessDayAdjust" => "previous_business_day" },
        series_start: saturday, after_time: saturday
      )
      expect(ctx[:next_occurrence].to_date).to eq(Date.new(2026, 1, 16))

      _result, ctx = run_from(
        { "frequency" => "monthly", "dayOfMonth" => 31, "monthEndPolicy" => "skip" },
        series_start: jan31, after_time: jan31
      )
      expect(ctx[:next_occurrence].to_date).to eq(Date.new(2026, 3, 31))

      _result, ctx = run_from("frequency" => "weekly", "weekdays" => %w[mon])
      expect(ctx[:next_occurrence].to_date).to eq(Date.new(2026, 1, 19))
    end

    it "fails with translated messages for an invalid anchor and no occurrence" do
      ctx = { series_start: "nope", errors: [] }
      result = execute(described_class.sample_input.merge("startVariable" => "series_start"), ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.next_occurrence.invalid_anchor")])

      until_at = origin + 1.hour
      result, ctx = run_from({ "untilVariable" => "until_at" }, until_at: until_at)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.next_occurrence.no_occurrence")])
    end
  end

  describe "#validate_config" do
    it "rejects an unknown timezone, cron, time of day and weekday" do
      expect(errors(base.merge("timezone" => "Bogus/Zone")).map(&:code)).to include(:invalid_timezone)
      expect(errors(base.merge("frequency" => "cron", "cronExpression" => "not cron")).map(&:code))
        .to include(:invalid_cron)
      expect(errors(base.merge("timeOfDay" => "25:00")).map(&:code)).to include(:invalid_time_of_day)
      expect(errors(base.merge("frequency" => "weekly", "weekdays" => ["funday"])).map(&:code))
        .to include(:invalid_weekday)
    end
  end
end
