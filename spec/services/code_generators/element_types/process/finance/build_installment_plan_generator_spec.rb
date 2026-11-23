# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Finance::BuildInstallmentPlanGenerator do
  let(:element) { { "config" => described_class.sample_input } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context)
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[installments installment_totals])
    expect(result.ok?).to be_truthy, result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"build_installment_plan.failed",
          FlowchartRuntime::Installments::Error
        ) do
          plan = FlowchartRuntime::Installments.build(
            ctx,
            principal: ctx[:loan_amount],
            rate_override: ctx[:interest_rate],
            start_date: ctx[:start_date]
          )
          ctx[:installments] = plan && plan["schedule"]
          ctx[:installment_totals] = plan && plan["totals"]
        end
      end
    RUBY
  end

  it "emits method, frequency, and rounding when they differ from runtime defaults" do
    code = generated_step(
      described_class.sample_input.merge("method" => "flat", "frequency" => "weekly", "roundingMode" => "floor")
    )
    expect(code).to include('method: "flat"')
    expect(code).to include('frequency: "weekly"')
    expect(code).to include('rounding_mode: "floor"')
  end

  it "requires principal" do
    expect(errors({}).map(&:field)).to include("principal")
  end

  it "emits distinct source for every frequency, method, and rounding option" do
    {
      "frequency" => described_class::FREQUENCIES,
      "method" => described_class::METHODS,
      "roundingMode" => described_class::ROUNDING_MODES
    }.each do |field, values|
      bodies = values.map { |value| body(described_class.sample_input.merge(field => value)) }
      expect(bodies.uniq.size).to eq(values.size), field
    end
  end

  describe "behaviour" do
    let(:base_ctx) { { loan_amount: 10_000, errors: [] } }

    it "builds a 12-month 12% annuity of 888.49" do
      travel_to Time.zone.local(2026, 1, 15, 12) do
        config = described_class.sample_input.merge("annualRate" => 12, "periods" => 12, "method" => "annuity")
        result = execute(config, base_ctx)
        expect(result[:outcome]).to be_truthy
        expect(base_ctx[:installments].first["payment"]).to eq("888.49")
        expect(base_ctx[:installments].first["due_date"]).to eq("2026-02-15")
        expect(base_ctx[:installment_totals]["principal"]).to eq("10000.00")
      end
    end

    described_class::METHODS.each do |method|
      it "executes method #{method}" do
        config = described_class.sample_input.merge("method" => method, "annualRate" => 12, "periods" => 4)
        expect(execute(config, base_ctx.merge(loan_amount: 1_000))[:outcome]).to be_truthy
      end
    end

    described_class::FREQUENCIES.each do |frequency|
      it "executes frequency #{frequency}" do
        travel_to Time.zone.local(2026, 1, 15, 12) do
          ctx = { loan_amount: 1_000, errors: [] }
          config = described_class.sample_input.merge("frequency" => frequency, "periods" => 2)
          expect(execute(config, ctx)[:outcome]).to be_truthy
          expect(ctx[:installments].first["due_date"]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
        end
      end
    end

    described_class::ROUNDING_MODES.each do |mode|
      it "executes roundingMode #{mode}" do
        config = described_class.sample_input.merge("roundingMode" => mode, "annualRate" => 12, "periods" => 3)
        expect(execute(config, { loan_amount: 1_000 })[:outcome]).to be_truthy
      end
    end

    [true, false].each do |flag|
      it "executes finalPaymentAdjust #{flag}" do
        config = described_class.sample_input.merge("finalPaymentAdjust" => flag, "periods" => 3)
        expect(execute(config, { loan_amount: 1_000 })[:outcome]).to be_truthy
      end
    end

    it "fails when the down payment exceeds principal" do
      ctx = { loan_amount: 100, errors: [] }
      result = execute(described_class.sample_input.merge("downPayment" => 150), ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.build_installment_plan.down_payment_exceeds_principal"))
    end
  end
end
