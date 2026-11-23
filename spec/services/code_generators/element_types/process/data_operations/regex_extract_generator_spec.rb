# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::RegexExtractGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "text", "resultVar" => "match", "pattern" => "(\\d+)", "operation" => "match" }
  end
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
        FlowchartRuntime::Step.attempt(ctx, :"regex_extract.failed", FlowchartRuntime::Regex::Error) do
          ctx[:match] = FlowchartRuntime::Regex.apply(ctx[:invoice_number], pattern: "(\\\\d+)")
          true
        end
      end
    RUBY
  end

  it "emits replace with a replacement string" do
    config = described_class.sample_input.merge("operation" => "replace", "pattern" => "\\d+", "replacement" => "X")
    expect(generated_step(config)).to include('operation: "replace"')
    expect(generated_step(config)).to include('replacement: "X"')
  end

  it "emits capture_group when it is not zero" do
    expect(generated_step(described_class.sample_input.merge("captureGroup" => 1)))
      .to include("capture_group: 1")
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  described_class::OPERATIONS.each do |operation|
    it "emits a BodyLint-clean body for operation #{operation}" do
      config = described_class.sample_input.merge("operation" => operation, "replacement" => "x")
      expect(generate(config).validate_config(config)).to eq([])
      expect(body(config)).to include("FlowchartRuntime::Regex.apply")
      lint!(config)
    end
  end

  it "extracts the first capture at runtime" do
    result = execute(base.merge("captureGroup" => 1), { text: "invoice 123" })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:match]).to eq("123")
  end

  it "replaces matches at runtime" do
    result = execute(base.merge("operation" => "replace", "pattern" => "\\d+", "replacement" => "X"), { text: "a12b" })
    expect(result[:ctx][:match]).to eq("aXb")
  end

  it "rejects an invalid pattern" do
    expect(codes(base.merge("pattern" => "["))).to include(:invalid_pattern)
  end

  it "requires replacement for replace" do
    expect(codes(base.merge("operation" => "replace", "replacement" => ""))).to include(:required)
  end
end
