# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::StringManipulateGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "text", "operation" => "upcase", "resultVar" => "text" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def codes(config)
    generate(config).validate_config(config).map { |error| error.respond_to?(:code) ? error.code : error }
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"string_manipulate.failed",
          FlowchartRuntime::Text::Error
        ) do
          ctx[:text] = FlowchartRuntime::Text.apply(ctx[:customer_name], operation: "strip")
          true
        end
      end
    RUBY
  end

  it "emits url_safe for base64_encode" do
    code = generated_step(described_class.sample_input.merge("operation" => "base64_encode", "urlSafe" => true))
    expect(code).to include('operation: "base64_encode"')
    expect(code).to include("url_safe: true")
  end

  it "emits regex_escape for gsub" do
    config = described_class.sample_input.merge("operation" => "gsub", "pattern" => ".", "regexEscape" => true)
    expect(generated_step(config)).to include("regex_escape: true")
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  described_class::OPERATIONS.each do |operation|
    it "emits a BodyLint-clean body for operation #{operation}" do
      config = described_class.sample_input.merge("operation" => operation)
      config["pattern"] = "x" if %w[replace gsub].include?(operation)
      next if generate(config).validate_config(config).any?

      expect(body(config)).to include("FlowchartRuntime::Text.apply")
      expect(body(config)).to include(%(operation: "#{operation}"))
      lint!(config)
    end
  end

  it "upcases a string at runtime" do
    result = execute(base, { text: "ada" })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:text]).to eq("ADA")
  end

  it "does not emit encoding or pipeline kwargs" do
    expect(generated_step(base)).not_to include("encoding:")
    expect(generated_step(base)).not_to include("operations:")
  end

  it "encodes Base64 at runtime" do
    result = execute(base.merge("operation" => "base64_encode"), { text: "hello" })
    expect(result[:ctx][:text]).to eq("aGVsbG8=")
  end

  it "fails with a translated message for invalid Base64" do
    result = execute(base.merge("operation" => "base64_decode"), { text: "%%%" })
    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.string_manipulate.failed", reason: "Error"))
  end

  it "squishes, titleizes, parameterizes, and masks the middle" do
    expect(execute(base.merge("operation" => "squish"), { text: "  a   b  " })[:ctx][:text]).to eq("a b")
    expect(execute(base.merge("operation" => "titleize"), { text: "hello world" })[:ctx][:text]).to eq("Hello World")
    expect(execute(base.merge("operation" => "parameterize"), { text: "Hello World" })[:ctx][:text]).to eq("hello-world")
    masked = execute(base.merge("operation" => "mask_middle", "length" => 1, "padChar" => "*"), { text: "123456" })
    expect(masked[:ctx][:text]).to eq("1****6")
  end
end
