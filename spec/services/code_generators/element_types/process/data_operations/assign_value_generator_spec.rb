# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator do
  let(:context) { {} }
  let(:base) { { "resultVar" => "assigned", "valueType" => "string", "stringValue" => "hello" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:assigned] = (ctx[:count].to_i + 1)
        true
      end
    RUBY
  end

  it "generates a string assignment" do
    expect(generated_step(base)).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:assigned] = "hello"
        true
      end
    RUBY
  end

  def body(config = base) = described_class.new({ "config" => config }, context).generate_body
  def errors(config) = described_class.new(element, context).validate_config(config)
  def codes(config) = errors(config).map(&:code)

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
    described_class::VALUE_TYPES.each do |value_type|
      it "emits a BodyLint-clean body for valueType #{value_type}" do
        config = described_class.sample_input.merge("valueType" => value_type)
        instance = described_class.new({ "config" => config }, context)
        next if instance.validate_config(config).any?

        result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: %w[resultVar assigned])
        expect(result.ok?).to be(true), result.violations.inspect
      end
    end

    it "assigns a string literal" do
      expect(body).to include('ctx[:assigned] = "hello"')
    end

    it "assigns an integer literal" do
      expect(body("resultVar" => "count", "valueType" => "integer", "integerValue" => 42)).to include("ctx[:count] = 42")
    end

    it "assigns a float literal" do
      expect(body("resultVar" => "pi", "valueType" => "float", "floatValue" => 3.14)).to include("ctx[:pi] = 3.14")
    end

    it "assigns boolean true and false" do
      expect(body("resultVar" => "ok", "valueType" => "boolean", "booleanValue" => true)).to include("ctx[:ok] = true")
      expect(body("resultVar" => "ok", "valueType" => "boolean", "booleanValue" => false)).to include("ctx[:ok] = false")
    end

    it "assigns nil for the null value type" do
      expect(body("resultVar" => "n", "valueType" => "null")).to include("ctx[:n] = nil")
    end

    it "assigns an array literal from scalars or a key/value list" do
      expect(body("resultVar" => "list", "valueType" => "array", "arrayValue" => [1, "two", true]))
        .to include("ctx[:list] = [1, \"two\", true]")
      expect(body("resultVar" => "list", "valueType" => "array", "arrayValue" => [{ "key" => "a", "value" => "alpha" }]))
        .to include("ctx[:list] = [\"alpha\"]")
    end

    it "assigns a hash literal" do
      expect(body("resultVar" => "h", "valueType" => "hash", "hashValue" => [{ "key" => "name", "value" => "John" }]))
        .to include("\"name\"")
    end

    it "assigns an expression" do
      expect(body("resultVar" => "x", "valueType" => "expression", "valueExpression" => "ctx[:a] + ctx[:b]"))
        .to include("ctx[:a] + ctx[:b]")
    end

    it "copies a ctx_ref" do
      expect(body("resultVar" => "dest", "valueType" => "ctx_ref", "ctxRefVariable" => "source"))
        .to include("ctx[:dest] = ctx[:source]")
    end

    it "does not emit random generation (use generate_id)" do
      expect(described_class::VALUE_TYPES).not_to include("random")
      expect(body("valueType" => "first_present", "candidates" => %w[name])).not_to include("Collections.random")
    end

    it "emits first_present through Collections" do
      code = body("valueType" => "first_present", "candidates" => %w[preferred_name name], "resultVar" => "display")
      expect(code).to include("FlowchartRuntime::Collections.first_present_from_ctx")
      expect(code).to include("preferred_name")
      expect(code).not_to include("predicate:")
    end
  end

  describe "#validate_config" do
    it "requires an expression when valueType is expression" do
      expect(codes("valueType" => "expression")).to include(:required)
    end

    it "requires ctxRefVariable when valueType is ctx_ref" do
      expect(errors("valueType" => "ctx_ref").map(&:field)).to include("ctxRefVariable")
    end

    it "rejects unknown valueType" do
      expect(codes("valueType" => "bogus")).to include(:not_in_list)
    end

    it "rejects the removed random valueType" do
      expect(codes("valueType" => "random")).to include(:not_in_list)
    end
  end

  describe "behaviour" do
    it "writes the integer into ctx" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "resultVar" => "count", "valueType" => "integer", "integerValue" => 42 },
        ctx: {}
      )
      expect(result[:validation_errors]).to eq([])
      expect(result[:outcome]).to eq(true)
      expect(result[:ctx][:count]).to eq(42)
    end

    it "returns the first present candidate, skipping blanks" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "resultVar" => "display",
          "valueType" => "first_present",
          "candidates" => %w[preferred_name name],
          "literalCandidates" => ["Anonymous"]
        },
        ctx: { preferred_name: "", name: "Ada" }
      )
      expect(result[:ctx][:display]).to eq("Ada")
    end

    it "succeeds when assigning nil" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "resultVar" => "n", "valueType" => "null" },
        ctx: {}
      )
      expect(result[:outcome]).to eq(true)
      expect(result[:ctx][:n]).to be_nil
    end
  end
end
