# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Workflow::EvaluateRulesGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def run_body(config, ctx)
    body = generate(config)
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  let(:amount_rules) do
    [
      { "key" => "ctx[:amount].to_d > 1000", "value" => '"vip"' },
      { "key" => "true", "value" => '"standard"' }
    ]
  end

  let(:numeric_rules) do
    [
      { "key" => "ctx[:amount].to_f > 0", "value" => "10" },
      { "key" => "ctx[:amount].to_f > 5", "value" => "3" }
    ]
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "rejects an empty rules list and an unsafe rule expression at emit time" do
    expect(errors(described_class.sample_input.merge("rules" => [])).map(&:code)).to include(:required)
    unsafe = described_class.sample_input.merge(
      "rules" => [{ "key" => "1); Kernel.raise('pwn'); (1", "value" => "1" }]
    )
    expect(errors(unsafe).map(&:code)).to include(:invalid_expression)
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"evaluate_rules.failed",
          FlowchartRuntime::RulesTable::Error
        ) do
          rules = [
            [-> { (ctx[:amount].to_d > 1000) }, -> { "vip" }],
            [-> { true }, -> { "standard" }]
          ]
          result = FlowchartRuntime::RulesTable.evaluate(ctx, rules, hit_policy: "first")
          next false unless result
          ctx[:rule_result] = result[:result]
          ctx[:matched_rules] = result[:matched]
          result
        end
      end
    RUBY
  end

  it "emits lambdas and re-checks ExpressionSafety" do
    src = generate
    expect(src).to include("FlowchartRuntime::RulesTable.evaluate")
    expect(src).to include('[-> { (ctx[:amount].to_d > 1000) }, -> { "vip" }]')
    expect(src).to include('[-> { true }, -> { "standard" }]')
    expect(src).not_to include("I18n.t")
  end

  it "emits collect unique_results" do
    expect(generated_step(described_class.sample_input.merge("hitPolicy" => "collect", "uniqueResults" => true)))
      .to include('hit_policy: "collect"', "unique_results: true")
  end

  described_class::HIT_POLICIES.each do |policy|
    it "emits a BodyLint-clean body for hitPolicy #{policy}" do
      config = described_class.sample_input.merge("hitPolicy" => policy)
      src = generate(config)
      result = CodeGenerators::BodyLint.check(src, outputs: %w[rule_result matched_rules])
      expect(result.ok?).to be_truthy, "#{result.violations.inspect}\n#{src}"
    end
  end

  it "emits a distinct body for every hitPolicy and onNoMatch" do
    policies = described_class::HIT_POLICIES.map { |value| generate(described_class.sample_input.merge("hitPolicy" => value)) }
    expect(policies.uniq.size).to eq(described_class::HIT_POLICIES.size)
    matches = described_class::ON_NO_MATCH.map { |value| generate(described_class.sample_input.merge("onNoMatch" => value)) }
    expect(matches.uniq.size).to eq(described_class::ON_NO_MATCH.size)
  end

  it "does not emit uniqueResults while hitPolicy is not collect" do
    base = generate(described_class.sample_input)
    leaked = generate(described_class.sample_input.merge("uniqueResults" => true))
    expect(leaked).to eq(base)
  end

  describe "behaviour" do
    it "returns the first matching result" do
      ctx = { amount: 1500, errors: [] }
      expect(run_body(described_class.sample_input.merge("rules" => amount_rules), ctx)).to be_truthy
      expect(ctx[:rule_result]).to eq("vip")
      expect(ctx[:matched_rules]).to eq([1])
    end

    described_class::HIT_POLICIES.each do |policy|
      it "executes hitPolicy #{policy} against a real ctx" do
        ctx = { amount: 9, errors: [] }
        config = described_class.sample_input.merge("hitPolicy" => policy, "rules" => numeric_rules)
        result = execute(config, ctx)
        expect(result[:validation_errors]).to eq([])
        case policy
        when "first"
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq(10)
        when "collect"
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq([10, 3])
        when "sum"
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq(BigDecimal("13"))
        when "count"
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq(2)
        when "min"
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq(BigDecimal("3"))
        when "max"
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq(BigDecimal("10"))
        when "any"
          expect(result[:outcome]).to eq(false)
          expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.evaluate_rules.any_conflict")])
        end
      end
    end

    it "uniques collected results when uniqueResults is true" do
      ctx = { amount: 9, errors: [] }
      config = described_class.sample_input.merge(
        "hitPolicy" => "collect",
        "uniqueResults" => true,
        "rules" => [
          { "key" => "true", "value" => '"a"' },
          { "key" => "true", "value" => '"a"' },
          { "key" => "true", "value" => '"b"' }
        ]
      )
      execute(config, ctx)
      expect(ctx[:rule_result]).to eq(%w[a b])
      expect(ctx[:matched_rules]).to eq([1, 2, 3])
    end

    described_class::ON_NO_MATCH.each do |mode|
      it "handles onNoMatch #{mode} when nothing matches" do
        ctx = { amount: 0, errors: [] }
        config = described_class.sample_input.merge(
          "rules" => [{ "key" => "ctx[:amount].to_f > 100", "value" => '"vip"' }],
          "defaultValue" => '"none"',
          "onNoMatch" => mode
        )
        result = execute(config, ctx)
        if mode == "fail"
          expect(result[:outcome]).to eq(false)
          expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.evaluate_rules.no_match")])
        else
          expect(result[:outcome]).to be_truthy
          expect(ctx[:rule_result]).to eq("none")
          expect(ctx[:matched_rules]).to eq([])
        end
      end
    end

    it "fails when sum sees a non-numeric result" do
      ctx = { amount: 9, errors: [] }
      result = execute(described_class.sample_input.merge("hitPolicy" => "sum", "rules" => amount_rules), ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.evaluate_rules.non_numeric")])
    end
  end
end
