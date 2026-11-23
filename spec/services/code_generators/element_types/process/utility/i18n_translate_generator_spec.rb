# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::I18nTranslateGenerator do
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[translated])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"i18n_translate.failed",
          FlowchartRuntime::Translate::Error
        ) do
          ctx[:translated] = FlowchartRuntime::Translate.call("greeting.hello")
          true
        end
      end
    RUBY
  end

  it "emits Translate.call and never I18n.t" do
    expect(body).to include("FlowchartRuntime::Translate.call")
    expect(body).not_to include("I18n.t")
  end

  it "emits locale and interpolation bindings" do
    code = generated_step(
      described_class.sample_input.merge(
        "locale" => "en",
        "interpolations" => [{ "key" => "name", "value" => "person" }]
      )
    )
    expect(code).to include('locale: "en"')
    expect(code).to include("name: ctx[:person]")
  end

  describe "behaviour" do
    before do
      I18n.backend.store_translations(:en, greeting: { hello: "Hello %{name}" })
      I18n.backend.store_translations(:"zh-CN", greeting: { hello: "你好 %{name}" })
    end

    it "interpolates from context paths" do
      result = execute(
        described_class.sample_input.merge(
          "key" => "greeting.hello",
          "locale" => "en",
          "interpolations" => [{ "key" => "name", "value" => "person" }]
        ),
        { person: "Ada" }
      )
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:translated]).to eq("Hello Ada")
    end

    it "reads localeFrom the context when set" do
      result = execute(
        described_class.sample_input.merge(
          "key" => "greeting.hello",
          "localeFrom" => "visitor_locale",
          "interpolations" => [{ "key" => "name", "value" => "person" }]
        ),
        { visitor_locale: "zh-CN", person: "Ada" }
      )
      expect(result[:ctx][:translated]).to eq("你好 Ada")
    end

    it "fails with a translated message when raiseOnMissing is set" do
      result = execute(
        described_class.sample_input.merge("key" => "missing.none", "raiseOnMissing" => true),
        { errors: [] }
      )
      expect(result[:outcome]).to be(false)
      expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.i18n_translate.failed", reason: "Error"))
    end
  end
end
