# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::FilterCollectionGenerator do
  let(:context) { {} }
  let(:base) do
    {
      "sourceVariable" => "items",
      "resultVar" => "filtered",
      "returns" => "items",
      "filterMode" => "single",
      "filterField" => "status",
      "filterOperator" => "eq",
      "filterValue" => "active"
    }
  end
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:filtered] = FlowchartRuntime::Collections.filter(
          Array(ctx[:items]),
          returns: "items",
          field: "status"
        )
        true
      end
    RUBY
  end

  it "generates a split into matched and rejected" do
    expect(generated_step(base.merge("returns" => "split", "rejectedVar" => "rejected"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        matched, rejected = FlowchartRuntime::Collections.filter(
          Array(ctx[:items]),
          returns: "split",
          field: "status",
          compare: "active"
        )
        ctx[:filtered] = matched
        ctx[:rejected] = rejected
        true
      end
    RUBY
  end

  def body(config = base) = described_class.new({ "config" => config }, context).generate_body
  def errors(config) = described_class.new(element, context).validate_config(config)

  describe "schema defaults and sample" do
    it "has only required errors for schema defaults" do
      defaults = described_class._config_schema.defaults
      unexpected = described_class.new({ "config" => defaults }, context).validate_config(defaults)
                    .reject { |error| error.code == :required }
      expect(unexpected).to eq([])
    end

    it "accepts sample_input and compiles" do
      sample = described_class.sample_input
      instance = described_class.new({ "config" => sample, "label" => "test_step" }, context)
      expect(instance.validate_config(sample)).to eq([])
      expect { RubyVM::InstructionSequence.compile(instance.generate_step_method) }.not_to raise_error
    end
  end

  describe "#generate_body" do
    described_class::RETURNS.each do |mode|
      it "emits a BodyLint-clean body for returns #{mode}" do
        config = described_class.sample_input.merge("returns" => mode, "rejectedVar" => "rejected")
        instance = described_class.new({ "config" => config }, context)
        next if instance.validate_config(config).any?

        result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: %w[resultVar rejectedVar filtered rejected])
        expect(result.ok?).to be(true), "#{result.violations.inspect}\n#{instance.generate_body}"
      end
    end

    it "delegates to Collections.filter" do
      expect(body).to include("FlowchartRuntime::Collections.filter")
      expect(body).to include("returns: \"items\"")
    end

    it "assigns both outputs for split" do
      code = body(base.merge("returns" => "split", "rejectedVar" => "rejected"))
      expect(code).to include("ctx[:filtered] = matched")
      expect(code).to include("ctx[:rejected] = rejected")
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable" do
      expect(errors({}).map(&:field)).to include("sourceVariable")
    end
  end

  describe "behaviour" do
    let(:items) do
      [
        { status: "active", amount: 10 },
        { status: "draft", amount: 3 },
        { status: "active", amount: 2 }
      ]
    end

    it "returns matching items" do
      result = CodeGenerators::TestRunner.execute(described_class, config: base, ctx: { items: items })
      expect(result[:ctx][:filtered]).to eq([items[0], items[2]])
    end

    it "splits matches from rejects" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("returns" => "split", "rejectedVar" => "rejected"),
        ctx: { items: items }
      )
      expect(result[:ctx][:filtered]).to eq([items[0], items[2]])
      expect(result[:ctx][:rejected]).to eq([items[1]])
    end

    it "returns the first match" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("returns" => "first"),
        ctx: { items: items }
      )
      expect(result[:ctx][:filtered]).to eq(items[0])
    end

    it "returns a boolean for any" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("returns" => "any"),
        ctx: { items: items }
      )
      expect(result[:ctx][:filtered]).to eq(true)
    end

    it "returns a count" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("returns" => "count"),
        ctx: { items: items }
      )
      expect(result[:ctx][:filtered]).to eq(2)
    end

    it "emits limit and keeps only the first N matches" do
      expect(body(base.merge("limit" => 1))).to include("limit: 1")
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("limit" => 1),
        ctx: { items: items }
      )
      expect(result[:ctx][:filtered]).to eq([items[0]])
    end

    it "stores a literal default when first finds nothing" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("returns" => "first", "filterValue" => "gone", "defaultValue" => "none"),
        ctx: { items: items }
      )
      expect(result[:ctx][:filtered]).to eq("none")
    end
  end
end
