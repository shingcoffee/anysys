# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::MathOperationGenerator do
  let(:context) { {} }
  let(:base) { { "operation" => "add", "sourceVariable" => "a", "otherVariable" => "b", "resultVar" => "number" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"math_operation.failed",
          FlowchartRuntime::Numbers::Error
        ) do
          ctx[:number] = FlowchartRuntime::Numbers.apply(
            ctx[:subtotal],
            operation: "add",
            other: ctx[:tax]
          )
          true
        end
      end
    RUBY
  end

  it "omits default kwargs and emits divide_by_zero when it is not raise" do
    code = generated_step(described_class.sample_input.merge("operation" => "divide", "divideByZero" => "nil"))
    expect(code).to include('divide_by_zero: "nil"')
    expect(code).not_to include("rounding_mode:")
    expect(code).not_to include("min_value:")
  end

  it "emits clamp bounds that differ from the runtime default" do
    code = generated_step(described_class.sample_input.merge("operation" => "clamp", "minValue" => 0, "maxValue" => 10))
    expect(code).to include("max_value: 10")
    expect(code).not_to include("min_value:")
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  described_class::OPERATIONS.each do |operation|
    it "emits a BodyLint-clean body for operation #{operation}" do
      config = described_class.sample_input.merge("operation" => operation, "sourceVariable" => "a", "otherVariable" => "b")
      next if generate(config).validate_config(config).any?

      expect(body(config)).to include("FlowchartRuntime::Numbers.apply")
      expect(body(config)).to include(%(operation: "#{operation}"))
      lint!(config)
    end
  end

  it "adds two numbers at runtime with BigDecimal" do
    result = execute(base, { a: 7, b: 2 })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:number]).to eq(BigDecimal("9"))
  end

  it "adds decimal money without binary float error" do
    result = execute(base, { a: "0.1", b: "0.2" })
    expect(result[:ctx][:number]).to eq(BigDecimal("0.3"))
  end

  it "returns nil on divide-by-zero when policy is nil" do
    result = execute(base.merge("operation" => "divide", "divideByZero" => "nil"), { a: 1, b: 0 })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:number]).to be_nil
  end

  it "fails with a translated message when divide-by-zero raises" do
    result = execute(base.merge("operation" => "divide", "divideByZero" => "raise"), { a: 1, b: 0 })
    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.math_operation.failed", reason: "Error"))
  end

  it "computes percent of the other operand" do
    result = execute(base.merge("operation" => "percent"), { a: 25, b: 200 })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:number]).to eq(BigDecimal("12.5"))
  end

  it "clamps a value between minValue and maxValue" do
    result = execute(base.merge("operation" => "clamp", "minValue" => 0, "maxValue" => 10), { a: 15, b: 0 })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:number]).to eq(BigDecimal("10"))
  end

  it "rounds with roundingMode when precision is set" do
    result = execute(base.merge("operation" => "divide", "precision" => 0, "roundingMode" => "floor"), { a: 5, b: 2 })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:number]).to eq(2)
  end
end
