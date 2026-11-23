# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::SchedulingTime::DeadlineCheckGenerator do
  let(:context) { {} }
  let(:base) { { "deadlineVariable" => "due_date", "resultVar" => "deadline_status" } }
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
          :"deadline_check.failed",
          FlowchartRuntime::Deadline::Error
        ) do
          check = FlowchartRuntime::Deadline.check(deadline: ctx[:deadline])
          ctx[:deadline_status] = check[:status]
          ctx[:deadline_breached] = check[:breached]
          ctx[:deadline_at_risk] = check[:at_risk]
          true
        end
      end
    RUBY
  end

  it "fails the step when behaviorOnBreach is fail" do
    expect(generated_step(described_class.sample_input.merge("behaviorOnBreach" => "fail")))
      .to include('return FlowchartRuntime::Step.fail(ctx, :"deadline_check.breached") if check[:breached]')
  end

  it "lints a BodyLint-clean body for every format and behavior" do
    described_class::FORMATS.product(described_class::BEHAVIORS).each do |format, behavior|
      config = described_class.sample_input.merge("deadlineFormat" => format, "behaviorOnBreach" => behavior)
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[deadline_status deadline_breached deadline_at_risk])
      expect(result.ok?).to be(true), "#{format}/#{behavior}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  it "delegates to Deadline.check and never writes a signal" do
    code = body
    expect(code).to include("FlowchartRuntime::Deadline.check")
    expect(code).to include("ctx[:due_date]")
    expect(code).not_to include("ctx[:_signal]")
    expect(code).not_to include("Time.iso8601(ctx")
  end

  it "emits format and raise variants" do
    expect(body(base.merge("deadlineFormat" => "iso8601"))).to include('format: "iso8601"')
    expect(body(base.merge("deadlineFormat" => "rfc2822"))).to include('format: "rfc2822"')
    expect(body(base.merge("behaviorOnBreach" => "fail"))).to include(':"deadline_check.breached"')
    expect(body(base.merge("behaviorOnBreach" => "mark"))).not_to include("deadline_check.breached")
  end

  describe "behaviour" do
    it "marks a future deadline as not breached" do
      ctx = { due_date: Time.utc(2026, 10, 20, 12), reference: Time.utc(2026, 10, 19, 12) }
      result = execute(base.merge("referenceTime" => "reference"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:deadline_breached]).to be(false)
      expect(ctx[:deadline_status][:passed]).to be(false)
    end

    it "marks an overdue deadline and fails when behavior is raise" do
      ctx = { due_date: Time.utc(2026, 10, 18, 12), reference: Time.utc(2026, 10, 19, 12) }
      result = execute(base.merge("referenceTime" => "reference", "behaviorOnBreach" => "fail"), ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:deadline_breached]).to be(true)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.deadline_check.breached"))
    end

    it "does not write ctx[:_signal] on a breach" do
      ctx = { due_date: Time.utc(2026, 10, 18, 12), reference: Time.utc(2026, 10, 19, 12) }
      execute(base.merge("referenceTime" => "reference"), ctx)
      expect(ctx[:_signal]).to be_nil
    end

    it "marks at-risk when remaining time is within warningSeconds" do
      ctx = { due_date: Time.utc(2026, 10, 19, 12, 2), reference: Time.utc(2026, 10, 19, 12) }
      result = execute(base.merge("referenceTime" => "reference", "warningSeconds" => 300, "atRiskVar" => "deadline_at_risk"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:deadline_at_risk]).to be(true)
      expect(ctx[:deadline_breached]).to be(false)
    end

    it "emits warningSeconds and atRiskVar" do
      code = body(base.merge("warningSeconds" => 120, "atRiskVar" => "sla_risk"))
      expect(code).to include("warning_seconds: 120")
      expect(code).to include("ctx[:sla_risk] = check[:at_risk]")
      expect(body(base.merge("warningSeconds" => 0))).not_to include("warning_seconds: 120")
    end
  end

  describe "#validate_config" do
    it "rejects signal as behaviorOnBreach" do
      expect(errors(base.merge("behaviorOnBreach" => "signal")).map(&:code)).to include(:not_in_list)
    end
  end
end
