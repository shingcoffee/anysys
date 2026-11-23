# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::SchedulingTime::BusinessHoursCheckGenerator do
  let(:context) { {} }
  let(:schedule) do
    [{ "key" => "monday", "value" => "09:00-17:00" }, { "key" => "tuesday", "value" => "09:00-17:00" }]
  end
  let(:base) { { "schedule" => schedule, "timezone" => "UTC", "resultVar" => "hours_status" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(body(sample)) }.not_to raise_error
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"business_hours_check.failed",
          FlowchartRuntime::BusinessHours::Error
        ) do
          check = FlowchartRuntime::BusinessHours.open?(
            schedule: {
              "monday" => "09:00-17:00",
              "tuesday" => "09:00-17:00",
              "wednesday" => "09:00-17:00",
              "thursday" => "09:00-17:00",
              "friday" => "09:00-17:00"
            },
            at: Time.current,
            timezone: "UTC"
          )
          ctx[:hours_status] = check[:open]
          true
        end
      end
    RUBY
  end

  it "lints a BodyLint-clean body for every resultMode" do
    described_class::RESULT_MODES.each do |mode|
      config = described_class.sample_input.merge("resultMode" => mode)
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[hours_status])
      expect(result.ok?).to be(true), "#{mode}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  it "delegates to BusinessHours.open? in twelve lines or fewer" do
    code = body
    expect(code).to include("FlowchartRuntime::BusinessHours.open?")
    expect(code.lines.size).to be <= 12
    expect(code).not_to include("_parse_range")
    expect(code).not_to include("dstPolicy")
  end

  it "emits a distinct selection for each resultMode" do
    expect(body(base.merge("resultMode" => "bool"))).to include("check[:open]")
    expect(body(base.merge("resultMode" => "next_open"))).to include("check[:next_open_at]")
    expect(body(base.merge("resultMode" => "minutes_until_open"))).to include("check[:minutes_until_open]")
    added = body(base.merge("resultMode" => "add_business_minutes", "businessMinutes" => 90))
    expect(added).to include("FlowchartRuntime::BusinessHours.add_minutes")
    expect(added).to include("minutes: 90")
    expect(added).not_to include("check[:open]")
  end

  describe "behaviour" do
    it "reports open during a scheduled window" do
      ctx = { now: Time.utc(2026, 10, 19, 12) }
      result = execute(base.merge("timeVariable" => "now"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:hours_status]).to be(true)
    end

    it "returns the next opening on a holiday" do
      ctx = { now: Time.utc(2026, 10, 19, 12) }
      cfg = base.merge(
        "timeVariable" => "now",
        "resultMode" => "next_open",
        "holidays" => [{ "key" => "2026-10-19", "value" => "Closed" }]
      )
      execute(cfg, ctx)
      expect(ctx[:hours_status]).to eq(Time.utc(2026, 10, 20, 9))
    end

    it "adds business minutes onto the start time" do
      ctx = { now: Time.utc(2026, 10, 19, 16, 30) }
      cfg = base.merge(
        "timeVariable" => "now",
        "resultMode" => "add_business_minutes",
        "businessMinutes" => 60
      )
      execute(cfg, ctx)
      expect(ctx[:hours_status]).to eq(Time.utc(2026, 10, 20, 9, 30))
    end

    it "treats a lunch break as closed and reports minutes until the afternoon window" do
      ctx = { now: Time.utc(2026, 10, 19, 12, 30) }
      cfg = base.merge(
        "schedule" => [{ "key" => "monday", "value" => "09:00-12:00,13:00-17:00" }],
        "timeVariable" => "now",
        "resultMode" => "minutes_until_open"
      )
      execute(cfg, ctx)
      expect(ctx[:hours_status]).to eq(30)
    end

    it "accepts a lunch-break schedule at validation time" do
      expect(errors(base.merge("schedule" => [{ "key" => "monday", "value" => "09:00-12:00,13:00-17:00" }]))).to eq([])
    end
  end

  describe "#validate_config" do
    it "requires schedule" do
      expect(errors({}).map(&:field)).to include("schedule")
    end

    it "rejects an unknown timezone" do
      expect(errors(base.merge("timezone" => "Bogus/Zone")).map(&:code)).to include(:invalid_timezone)
    end

    it "rejects a malformed schedule day" do
      expect(errors(base.merge("schedule" => [{ "key" => "not-a-day", "value" => "09:00-17:00" }])).map(&:code))
        .to include(:invalid_schedule)
    end

    it "rejects overlapping lunch-break windows" do
      expect(errors(base.merge("schedule" => [{ "key" => "monday", "value" => "09:00-12:00,11:00-17:00" }])).map(&:code))
        .to include(:invalid_schedule)
    end
  end
end
