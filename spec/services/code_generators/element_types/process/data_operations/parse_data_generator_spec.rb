# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::ParseDataGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "raw_data", "resultVar" => "data", "format" => "json" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
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
        FlowchartRuntime::Step.attempt(ctx, :"parse_data.failed", FlowchartRuntime::Parse::Error) do
          ctx[:data] = FlowchartRuntime::Parse.apply(ctx[:payload], format: "json")
          true
        end
      end
    RUBY
  end

  it "always wraps parse errors in Step.attempt" do
    expect(generated_step).to include("FlowchartRuntime::Step.attempt")
    expect(generated_step).to include("FlowchartRuntime::Parse::Error")
  end

  it "emits csv kwargs that differ from runtime defaults" do
    config = described_class.sample_input.merge(
      "format" => "csv", "skipRows" => 1, "colTypes" => [{ "key" => "qty", "value" => "integer" }]
    )
    code = generated_step(config)
    expect(code).to include('format: "csv"')
    expect(code).to include("skip_rows: 1")
    expect(code).to include('col_types: {"qty" => "integer"}')
    expect(code).not_to include("csv_headers:")
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  described_class::FORMATS.each do |format|
    it "emits a BodyLint-clean body for format #{format}" do
      config = described_class.sample_input.merge("format" => format)
      expect(generate(config).validate_config(config)).to eq([])
      expect(body(config)).to include("FlowchartRuntime::Parse.apply")
      expect(body(config)).to include(%(format: "#{format}"))
      lint!(config)
    end
  end

  it "parses JSON at runtime through FlowchartRuntime::Json" do
    result = execute(base, { raw_data: '{"count":2}' })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:data]).to eq("count" => 2)
  end

  it "parses CSV with absorbed parse_csv options" do
    config = base.merge("format" => "csv", "csvHeaders" => true, "skipRows" => 1, "csvDelimiter" => ",",
                        "colTypes" => [{ "key" => "qty", "value" => "integer" }])
    result = execute(config, { raw_data: "skip\nid,qty\n1,2\n" })
    expect(result[:ctx][:data]).to eq([{ "id" => "1", "qty" => 2 }])
  end

  it "fails with a translated message on invalid JSON" do
    result = execute(base, { raw_data: "{" })
    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.parse_data.failed", reason: "Error"))
  end
end
