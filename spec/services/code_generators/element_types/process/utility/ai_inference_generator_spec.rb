# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::AiInferenceGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {})
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[ai_response])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"ai_inference.failed",
          FlowchartRuntime::Ai::Error,
          FlowchartRuntime::Template::Error
        ) do
          response = FlowchartRuntime::Ai.complete(ctx, prompt_template: "Summarize: {{ text }}")
          ctx[:ai_response] = response
          response != false
        end
      end
    RUBY
  end

  it "emits json repair and onInvalidJson when outputFormat is json" do
    code = generated_step(described_class.sample_input.merge(
      "outputFormat" => "json", "jsonRepair" => true, "onInvalidJson" => "as_text"
    ))
    expect(code).to include('output_format: "json"', "json_repair: true", 'on_invalid_json: "as_text"')
  end

  it "does not offer vendor provider or tools fields" do
    names = described_class._config_schema.fields.map(&:name)
    expect(names).not_to include("provider", "tools")
  end

  it "emits a BodyLint-clean Llm-backed body" do
    code = body
    expect(code).to include("FlowchartRuntime::Ai.complete")
    expect(code).not_to include("RubyLLM")
    expect(code).not_to include("sleep")
    expect(CodeGenerators::BodyLint.check(code, outputs: %w[ai_response]).ok?).to be(true)
  end

  describe "behaviour" do
    let(:settings) do
      create(:ai_assistant_provider_settings, provider: "deepseek", generation_active: true,
                                              transcribe_active: false, api_key: "sk-test",
                                              config: { chat_model: "deepseek-chat" }.to_json)
    end

    before do
      AiAssistant::ProviderSettings.update_all(generation_active: false)
      settings
    end

    it "completes through the platform generation provider" do
      allow(Llm).to receive(:complete).and_return(outcome: :success, text: "Hello Ada", raw: {})
      ctx = { customer_id: 49, errors: [], text: "Ada" }

      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:ai_response]).to eq("Hello Ada")
      expect(Llm).to have_received(:complete).with(hash_including(
        provider: :deepseek, model: "deepseek-chat", api_key: "sk-test"
      ))
    end

    it "fails when no generation provider is configured" do
      settings.update!(generation_active: false)
      ctx = { customer_id: 49, errors: [], text: "Ada" }

      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.ai_inference.not_configured"))
    end

    it "repairs fenced JSON and stores the object" do
      allow(Llm).to receive(:complete).and_return(
        outcome: :success, text: "```json\n{\"ok\":true}\n```", raw: {}
      )
      ctx = { customer_id: 49, errors: [], text: "Ada" }

      result = execute(described_class.sample_input.merge("outputFormat" => "json", "jsonRepair" => true), ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:ai_response]).to eq("ok" => true)
    end

    it "returns the raw text when onInvalidJson is as_text" do
      allow(Llm).to receive(:complete).and_return(outcome: :success, text: "not-json", raw: {})
      ctx = { customer_id: 49, errors: [], text: "Ada" }

      result = execute(described_class.sample_input.merge("outputFormat" => "json", "onInvalidJson" => "as_text"), ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:ai_response]).to eq("not-json")
    end

    it "fails with a translated empty-response message" do
      allow(Llm).to receive(:complete).and_return(outcome: :success, text: "  ", raw: {})
      ctx = { customer_id: 49, errors: [] }

      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.ai_inference.empty"))
    end
  end
end
