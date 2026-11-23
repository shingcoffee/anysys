# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Finance::AllocateAmountGenerator do
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[allocations])
    expect(result.ok?).to be_truthy, result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"allocate_amount.failed",
          FlowchartRuntime::Allocation::Error
        ) do
          allocations = FlowchartRuntime::Allocation.split(ctx, amount: ctx[:total], method: "even")
          ctx[:allocations] = allocations
        end
      end
    RUBY
  end

  it "generates a ratio split from a weights variable" do
    expect(generated_step(described_class.sample_input.merge("method" => "ratio", "weightsVariable" => "weights"))).to include('method: "ratio"', "weights: ctx[:weights]")
  end

  it "requires amount and requires weights when method is ratio" do
    expect(errors({}).map(&:field)).to include("amount")
    expect(errors("amount" => "total", "method" => "ratio").map(&:field)).to include("weightsVariable")
  end

  it "emits distinct source for every method and remainder strategy" do
    methods = described_class::METHODS.map { |value| body(described_class.sample_input.merge("method" => value, "weightsVariable" => "weights")) }
    expect(methods.uniq.size).to eq(described_class::METHODS.size)
    remainders = described_class::REMAINDER_STRATEGIES.map { |value| body(described_class.sample_input.merge("remainderStrategy" => value)) }
    expect(remainders.uniq.size).to eq(described_class::REMAINDER_STRATEGIES.size)
  end

  describe "behaviour" do
    it "splits 100 into three even parts" do
      ctx = { total: 100 }
      result = execute(described_class.sample_input.merge("parts" => 3), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:allocations]).to eq(%w[33.34 33.33 33.33])
    end

    described_class::METHODS.each do |method|
      it "executes method #{method}" do
        ctx = { total: 100, weights: [50, 50] }
        config = described_class.sample_input.merge("method" => method, "weightsVariable" => "weights", "parts" => 2)
        expect(execute(config, ctx)[:outcome]).to be_truthy
        expect(ctx[:allocations].map { |row| BigDecimal(row) }.sum).to eq(BigDecimal("100.00"))
      end
    end

    described_class::REMAINDER_STRATEGIES.each do |strategy|
      it "executes remainderStrategy #{strategy}" do
        ctx = { total: 10, weights: [2, 3, 1] }
        config = described_class.sample_input.merge(
          "method" => "ratio", "weightsVariable" => "weights", "remainderStrategy" => strategy, "precision" => 0
        )
        expect(execute(config, ctx)[:outcome]).to be_truthy
        expect(ctx[:allocations].map { |row| BigDecimal(row) }.sum).to eq(BigDecimal("10"))
      end
    end

    it "fails when percent weights do not sum to 100" do
      ctx = { total: 100, weights: [10, 20], errors: [] }
      result = execute(
        described_class.sample_input.merge("method" => "percent", "weightsVariable" => "weights"),
        ctx
      )
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("allocate_amount.percent_total")
    end
  end
end
