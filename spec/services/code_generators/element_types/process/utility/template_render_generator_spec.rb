# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::TemplateRenderGenerator do
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[rendered])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"template_render.failed",
          FlowchartRuntime::Template::Error
        ) do
          ctx[:rendered] = FlowchartRuntime::Template.interpolate(ctx, "Hello {{ name }}")
          true
        end
      end
    RUBY
  end

  it "emits Template.interpolate" do
    expect(body).to include("FlowchartRuntime::Template.interpolate")
    expect(body).not_to include("engine:")
  end

  describe "behaviour" do
    it "renders from ctx keys when variables are empty" do
      result = execute(described_class.sample_input.merge("template" => "Hello {{ name }}"), { name: "Ada" })
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:rendered]).to eq("Hello Ada")
    end

    it "merges explicit variables over ctx" do
      result = execute(
        described_class.sample_input.merge(
          "template" => "Hello {{ name }}",
          "variables" => [{ "key" => "name", "value" => "person" }]
        ),
        { name: "ignored", person: "Ada" }
      )
      expect(result[:ctx][:rendered]).to eq("Hello Ada")
    end

    it "escapes interpolated values when outputFormat is html" do
      result = execute(
        described_class.sample_input.merge("template" => "<p>{{ name }}</p>", "outputFormat" => "html"),
        { name: "<b>Ada</b>" }
      )
      expect(result[:ctx][:rendered]).to eq("<p>&lt;b&gt;Ada&lt;/b&gt;</p>")
    end

    it "trims whitespace when flagged" do
      result = execute(
        described_class.sample_input.merge("template" => "  Hello {{ name }}  ", "trimWhitespace" => true),
        { name: "Ada" }
      )
      expect(result[:ctx][:rendered]).to eq("Hello Ada")
    end

    it "emits distinct source for outputFormat text vs html" do
      text = body(described_class.sample_input.merge("outputFormat" => "text"))
      html = body(described_class.sample_input.merge("outputFormat" => "html"))
      expect(text).not_to eq(html)
      expect(html).to include('output_format: "html"')
    end

    it "fails with a translated message when strict and missing" do
      result = execute(
        described_class.sample_input.merge("template" => "Hello {{ missing }}", "strictVariables" => true),
        { errors: [] }
      )
      expect(result[:outcome]).to be(false)
      expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.template_render.failed", reason: "Error"))
    end
  end
end
