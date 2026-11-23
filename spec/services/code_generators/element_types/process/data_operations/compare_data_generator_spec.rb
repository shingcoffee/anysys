# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::CompareDataGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "before", "otherVariable" => "after", "resultVar" => "diff" }
  end
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"compare_data.failed",
          FlowchartRuntime::HashDiff::Error
        ) do
          ctx[:diff] = FlowchartRuntime::HashDiff.compare(
            ctx[:before],
            ctx[:after],
            ignore_keys: ["updated_at"]
          )
          true
        end
      end
    RUBY
  end

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

  it "lints a BodyLint-clean body for every comparisonType" do
    described_class::COMPARISON_TYPES.each do |value|
      config = described_class.sample_input.merge("comparisonType" => value)
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[diff])
      expect(result.ok?).to be(true), "comparisonType=#{value}: #{result.violations.inspect}"
    end
  end

  it "emits distinct bodies for diff and equal" do
    expect(body(base.merge("comparisonType" => "diff")))
      .not_to eq(body(base.merge("comparisonType" => "equal")))
  end

  describe "behaviour" do
    it "diffs two hashes" do
      ctx = {
        before: { name: "old", removed: 1, updated_at: 1 },
        after: { name: "new", added: 2, updated_at: 2 }
      }
      result = execute(base.merge("ignoreKeys" => %w[updated_at]), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:diff][:added]).to eq(added: 2)
      expect(ctx[:diff][:removed]).to eq(removed: 1)
      expect(ctx[:diff][:changed]).to eq(name: { from: "old", to: "new" })
    end

    it "returns a boolean for equal without failing the step" do
      ctx = { before: { a: 1 }, after: { a: 2 } }
      result = execute(base.merge("comparisonType" => "equal"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:diff]).to be(false)
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable and otherVariable" do
      fields = errors({}).map(&:field)
      expect(fields).to include("sourceVariable", "otherVariable")
    end

    it "rejects the removed mode field values as comparisonType" do
      expect(errors(base.merge("comparisonType" => "keys")).map(&:code)).to include(:not_in_list)
    end
  end
end
