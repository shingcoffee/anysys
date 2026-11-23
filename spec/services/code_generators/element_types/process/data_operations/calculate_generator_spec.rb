# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::CalculateGenerator do
  let(:context) { {} }
  let(:base) { { "operation" => "sum", "sourceVariable" => "items", "fieldName" => "amount", "resultVar" => "total" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:total] = FlowchartRuntime::Collections.aggregate(Array(ctx[:items]), operation: "count")
        true
      end
    RUBY
  end

  def body(overrides = {}) = described_class.new({ "config" => base.merge(overrides) }, context).generate_body
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
    described_class::OPERATIONS.each do |operation|
      it "emits a BodyLint-clean body for operation #{operation}" do
        config = described_class.sample_input.merge("operation" => operation)
        instance = described_class.new({ "config" => config }, context)
        next if instance.validate_config(config).any?

        result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: %w[resultVar total])
        expect(result.ok?).to be(true), "#{result.violations.inspect}\n#{instance.generate_body}"
      end
    end

    it "delegates aggregates to Collections" do
      expect(body).to include("FlowchartRuntime::Collections.aggregate")
      expect(body).to include("ctx[:items]")
      expect(body).to include("operation: \"sum\"")
    end

    it "emits a concat separator when set" do
      code = body("operation" => "concat", "fieldName" => "name", "separator" => ", ")
      expect(code).to include('separator: ", "')
    end

    it "does not emit a custom Ruby collection expression" do
      expect(described_class::OPERATIONS).not_to include("custom")
      expect(body).not_to include("_collection")
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable" do
      expect(errors({}).map(&:field)).to include("sourceVariable")
    end

    it "rejects the removed custom operation" do
      expect(errors("operation" => "custom", "sourceVariable" => "items").map(&:code)).to include(:not_in_list)
    end
  end

  describe "behaviour" do
    let(:items) { [{ amount: 10 }, { amount: 5 }, { amount: nil }] }

    it "sums a field and ignores nils by default" do
      result = CodeGenerators::TestRunner.execute(described_class, config: base, ctx: { items: items })
      expect(result[:outcome]).to eq(true)
      expect(result[:ctx][:total]).to eq(15)
    end

    it "counts the collection" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("operation" => "count"),
        ctx: { items: items }
      )
      expect(result[:ctx][:total]).to eq(3)
    end

    it "returns zero for an empty collection" do
      result = CodeGenerators::TestRunner.execute(described_class, config: base, ctx: { items: [] })
      expect(result[:ctx][:total]).to eq(0)
    end

    it "multiplies values for product" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("operation" => "product", "ignoreNils" => true),
        ctx: { items: [{ amount: 2 }, { amount: 4 }] }
      )
      expect(result[:ctx][:total]).to eq(8)
    end

    it "joins field values with a separator" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: base.merge("operation" => "concat", "fieldName" => "amount", "separator" => "+"),
        ctx: { items: [{ amount: 1 }, { amount: 2 }] }
      )
      expect(result[:ctx][:total]).to eq("1+2")
    end
  end
end
