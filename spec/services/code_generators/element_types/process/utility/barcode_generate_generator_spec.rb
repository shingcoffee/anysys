# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::BarcodeGenerateGenerator do
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[barcode_image])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"barcode_generate.failed",
          FlowchartRuntime::Barcode::Error
        ) do
          ctx[:barcode_image] = FlowchartRuntime::Barcode.artifact(ctx[:sku])
          true
        end
      end
    RUBY
  end

  it "generates a QR step" do
    expect(generated_step(described_class.sample_input.merge("format" => "qr"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"barcode_generate.failed",
          FlowchartRuntime::Barcode::Error
        ) do
          ctx[:barcode_image] = FlowchartRuntime::Barcode.artifact(ctx[:sku], format: :qr)
          true
        end
      end
    RUBY
  end

  it "generates an SVG step with a human-readable label" do
    expect(generated_step(described_class.sample_input.merge("outputFormat" => "svg"))).to include("output: :svg", "include_text: true")
    expect(generated_step(described_class.sample_input.merge("outputFormat" => "svg"))).not_to include(".to_sym")
  end

  it "emits non-default QR level and output as symbol literals" do
    config = described_class.sample_input.merge("format" => "qr", "errorCorrection" => "H", "outputFormat" => "svg")
    expect(generated_step(config)).to include("level: :h", "output: :svg")
  end

  described_class::SYMBOLOGIES.each do |format|
    it "emits a BodyLint-clean body for format #{format}" do
      config = described_class.sample_input.merge("format" => format)
      next unless errors(config).empty?

      code = body(config)
      expect(code).to include("FlowchartRuntime::Barcode.artifact")
      expect(code).not_to include("Barby::")
      expect(CodeGenerators::BodyLint.check(code, outputs: %w[barcode_image]).ok?).to be(true)
    end
  end

  it "ignores includeText on raster output instead of failing validation" do
    config = described_class.sample_input.merge("outputFormat" => "png", "includeText" => true)
    expect(errors(config)).to eq([])
    expect(body(config)).not_to include("include_text")
  end

  describe "behaviour" do
    it "renders a PNG barcode artifact from ctx" do
      result = execute(described_class.sample_input, { sku: "ABC123" })
      expect(result[:outcome]).to be(true)
      artifact = result[:ctx][:barcode_image]
      expect(artifact["bytes"].b).to start_with("\x89PNG".b)
      expect(artifact["content_type"]).to eq("image/png")
      expect(artifact["data_uri"]).to start_with("data:image/png;base64,")
      expect(artifact["filename"]).to eq("barcode.png")
    end

    it "renders QR as format qr" do
      result = execute(described_class.sample_input.merge("format" => "qr"), { sku: "https://example.test" })
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:barcode_image]["bytes"].b).to start_with("\x89PNG".b)
      expect(result[:ctx][:barcode_image]["filename"]).to eq("qr.png")
    end

    it "draws a human-readable SVG label" do
      result = execute(
        described_class.sample_input.merge("outputFormat" => "svg", "includeText" => true, "textFont" => "Arial"),
        { sku: "ABC123" }
      )
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:barcode_image]["bytes"]).to include("<text")
      expect(result[:ctx][:barcode_image]["bytes"]).to include("ABC123")
      expect(result[:ctx][:barcode_image]["content_type"]).to eq("image/svg+xml")
    end

    it "fails with a translated message on invalid data" do
      result = execute(described_class.sample_input.merge("format" => "ean13"), { sku: "not-a-valid-ean", errors: [] })
      expect(result[:outcome]).to be(false)
      expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.barcode_generate.failed", reason: "Error"))
    end
  end
end
