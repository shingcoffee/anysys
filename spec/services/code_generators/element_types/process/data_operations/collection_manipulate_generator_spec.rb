# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::CollectionManipulateGenerator do
  let(:context) { {} }
  let(:base) do
    {
      "operation" => "map",
      "sourceVariable" => "items",
      "resultVar" => "collection",
      "fieldMappings" => [{ "key" => "name", "value" => "label" }]
    }
  end
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:collection] = FlowchartRuntime::Collections.map(
          Array(ctx[:items]),
          mappings: {"name" => "label"}
        )
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
        config = described_class.sample_input.merge("operation" => operation, "groupField" => "category",
                                                    "sortField" => "name",
                                                    "fields" => [{ "key" => "name", "value" => "label" }])
        instance = described_class.new({ "config" => config }, context)
        next if instance.validate_config(config).any?

        result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: %w[resultVar collection])
        expect(result.ok?).to be(true), "#{result.violations.inspect}\n#{instance.generate_body}"
      end
    end

    it "emits Collections.map for map" do
      expect(body).to include("FlowchartRuntime::Collections.map")
    end

    it "emits Collections.pluck with flatten for a single field" do
      code = body("operation" => "pluck", "fields" => [{ "key" => "name", "value" => "label" }])
      expect(code).to include("FlowchartRuntime::Collections.pluck")
      expect(code).to include("flatten: true")
    end

    it "does not expose zip or chunk" do
      expect(described_class::OPERATIONS).not_to include("zip", "chunk")
    end
  end

  describe "behaviour" do
    let(:items) { [{ name: "Ada", category: "a" }, { name: "Bob", category: "b" }, { name: "Ada", category: "a" }] }

    it "maps fields" do
      result = CodeGenerators::TestRunner.execute(described_class, config: base, ctx: { items: items })
      expect(result[:ctx][:collection]).to eq([{ label: "Ada" }, { label: "Bob" }, { label: "Ada" }])
    end

    it "plucks a single flattened field" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "operation" => "pluck",
          "sourceVariable" => "items",
          "fields" => [{ "key" => "name", "value" => "name" }]
        },
        ctx: { items: items }
      )
      expect(result[:ctx][:collection]).to eq(%w[Ada Bob Ada])
    end

    it "groups by a field" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "operation" => "group", "sourceVariable" => "items", "groupField" => "category" },
        ctx: { items: items }
      )
      expect(result[:ctx][:collection].keys).to contain_exactly("a", "b")
    end

    it "sorts by a field" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "operation" => "sort", "sourceVariable" => "items", "sortField" => "name", "sortDirection" => "desc" },
        ctx: { items: items }
      )
      expect(result[:ctx][:collection].map { |row| row[:name] }).to eq(%w[Bob Ada Ada])
    end

    it "uniques by a field" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "operation" => "unique", "sourceVariable" => "items", "uniqField" => "name" },
        ctx: { items: items }
      )
      expect(result[:ctx][:collection].map { |row| row[:name] }).to eq(%w[Ada Bob])
    end

    it "flattens nested arrays" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "operation" => "flatten", "sourceVariable" => "items", "depth" => 1 },
        ctx: { items: [[1, 2], [3]] }
      )
      expect(result[:ctx][:collection]).to eq([1, 2, 3])
    end
  end
end
