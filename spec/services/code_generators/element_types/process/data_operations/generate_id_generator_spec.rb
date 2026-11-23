# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::GenerateIdGenerator do
  let(:context) { {} }
  let(:base) { { "idType" => "uuid", "resultVar" => "id" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"generate_id.failed", FlowchartRuntime::Id::Error) do
          ctx[:id] = FlowchartRuntime::Id.generate(type: "uuid", prefix: "user", separator: "_")
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

  it "lints a BodyLint-clean body for every idType" do
    described_class::ID_TYPES.each do |type|
      config = described_class.sample_input.merge("idType" => type)
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[id])
      expect(result.ok?).to be(true), "#{type}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  it "emits distinct bodies for uuid, hex, and nanoid" do
    expect(body(base.merge("idType" => "uuid"))).not_to eq(body(base.merge("idType" => "hex")))
    expect(body(base.merge("idType" => "nanoid"))).not_to eq(body(base.merge("idType" => "uuid")))
  end

  describe "behaviour" do
    it "writes a uuid with prefix and separator" do
      allow(SecureRandom).to receive(:uuid).and_return("11111111-2222-4333-8444-555555555555")
      ctx = {}
      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:id]).to eq("user_11111111-2222-4333-8444-555555555555")
    end

    it "records a translated failure for an unknown type at runtime" do
      ctx = {}
      code = body(base)
      mutated = code.sub('type: "uuid"', 'type: "snowflake"')
      host = Class.new
      host.class_eval("def test_step(ctx, **)\n#{mutated}\nend")
      expect(host.new.test_step(ctx)).to eq(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.generate_id.failed", reason: "Error"))
    end
  end

  describe "#validate_config" do
    it "rejects an invalid idType" do
      expect(errors("idType" => "snowflake").map(&:code)).to include(:not_in_list)
    end

    it "accepts the business id types" do
      %w[uuid nanoid hex custom_pattern].each do |type|
        expect(errors("idType" => type)).to eq([])
      end
    end

    it "rejects programmer-only token types" do
      %w[ulid hash base58 urlsafe_base64 secure_random].each do |type|
        expect(errors("idType" => type).map(&:code)).to include(:not_in_list)
      end
    end
  end
end
