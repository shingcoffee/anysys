# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::TestRunner do
  describe ".run" do
    let(:generator_class) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }
    let(:config) { { "resultVar" => "assigned", "valueType" => "string", "stringValue" => "hello" } }
    let(:result) { described_class.run(generator_class, config: config) }

    it "returns a hash with code, body, inputs, outputs, validation_errors" do
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(:code, :body, :inputs, :outputs, :validation_errors)
    end

    it "body contains ctx references" do
      expect(result[:body]).to include("ctx[")
    end

    it "code wraps body with def step(ctx, **)" do
      expect(result[:code]).to include("(ctx, **)")
      expect(result[:code]).to match(/\Adef /)
      expect(result[:code].strip).to end_with("end")
    end

    it "outputs includes the target variable" do
      expect(result[:outputs]).to include("assigned")
    end

    it "validation_errors is an array" do
      expect(result[:validation_errors]).to be_an(Array)
    end

    context "with a generator that returns nil body" do
      let(:start_class) { CodeGenerators::ElementTypes::Start::StartGenerator }

      it "returns nil body and nil code" do
        result = described_class.run(start_class, config: {})
        expect(result[:body]).to be_nil
        expect(result[:code]).to be_nil
        expect(result[:inputs]).to eq([])
        expect(result[:outputs]).to eq([])
      end
    end

    context "with validation errors" do
      let(:config) { {} }

      it "passes through validation errors from the generator" do
        expect(result[:validation_errors]).to be_an(Array)
      end

      it "validates Decision before calling either emitter" do
        decision = CodeGenerators::ElementTypes::Decision::DecisionGenerator
        expect_any_instance_of(decision).not_to receive(:generate_body)
        expect_any_instance_of(decision).not_to receive(:generate_step_method)
        result = described_class.run(decision, config: {})
        expect(result[:validation_errors]).not_to be_empty
        expect(result.values_at(:body, :code, :inputs, :outputs)).to eq([nil, nil, [], []])
      end

      [nil, [], "text", 42, true, false].each do |root|
        it "rejects #{root.inspect} before constructing a generator" do
          expect(generator_class).not_to receive(:new)
          result = described_class.run(generator_class, config: root)
          expect(result[:validation_errors]).to eq([I18n.t("maint_platform.flash.code_generators.config_object_required")])
          expect(result[:code]).to be_nil
        end
      end

      it "localizes malformed-root validation in English and Simplified Chinese" do
        { en: "Configuration must be a JSON object", "zh-CN": "配置必须是 JSON 对象" }.each do |locale, message|
          I18n.with_locale(locale) do
            expect(described_class.run(generator_class, config: [])[:validation_errors]).to eq([message])
          end
        end
      end
    end

    context "with default config from sample_input" do
      it "uses empty hash when no config provided" do
        result = described_class.run(generator_class)
        expect(result).to be_a(Hash)
        expect(result[:body]).to be_a(String).or be_nil
      end
    end

    it "forwards optional context to the generator" do
      decision = CodeGenerators::ElementTypes::Decision::DecisionGenerator
      topology = {
        flowchart_topology: {
          outgoing_branches: [
            { "signal" => "Routes::Decision::Yes", "semantic" => "yes", "matchValue" => "true" },
            { "signal" => "Routes::Decision::No", "semantic" => "no", "matchValue" => "false" }
          ]
        }
      }
      result = described_class.run(decision, config: decision.sample_input, context: topology)
      expect(result[:validation_errors]).to be_empty
      expect(result[:code]).to include("Routes::Decision::Yes")
    end
  end

  describe ".execute" do
    let(:generator_class) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }

    it "invokes the compiled step and returns outcome + ctx" do
      result = described_class.execute(
        generator_class,
        config: { "resultVar" => "assigned", "valueType" => "integer", "integerValue" => 42 },
        ctx: {}
      )
      expect(result[:outcome]).to eq(true)
      expect(result[:ctx][:assigned]).to eq(42)
      expect(result[:validation_errors]).to be_empty
    end

    it "returns validation errors without executing invalid generated code" do
      result = described_class.execute(CodeGenerators::ElementTypes::Decision::DecisionGenerator, config: {})
      expect(result[:validation_errors]).not_to be_empty
      expect(result).not_to have_key(:outcome)
    end
  end
end
