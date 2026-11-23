# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::SerializeDataGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "data", "resultVar" => "serialized", "format" => "json" } }
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
        FlowchartRuntime::Step.attempt(
          ctx,
          :"serialize_data.failed",
          FlowchartRuntime::Serialize::Error
        ) do
          ctx[:serialized] = FlowchartRuntime::Serialize.apply(ctx[:order], format: "json")
          true
        end
      end
    RUBY
  end

  it "emits xml root options" do
    config = described_class.sample_input.merge("format" => "xml", "includeRoot" => true, "rootElement" => "order")
    code = generated_step(config)
    expect(code).to include('format: "xml"')
    expect(code).to include("include_root: true")
    expect(code).to include('root_element: "order"')
  end

  it "emits pretty: true for JSON" do
    expect(generated_step(described_class.sample_input.merge("pretty" => true))).to include("pretty: true")
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
      expect(body(config)).to include("FlowchartRuntime::Serialize.apply")
      expect(body(config)).to include(%(format: "#{format}"))
      expect(body(config)).not_to include("msgpack")
      lint!(config)
    end
  end

  it "serializes JSON at runtime" do
    result = execute(base, { data: { "count" => 2 } })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:serialized]).to eq('{"count":2}')
  end

  it "serializes csv and toml at runtime" do
    csv = execute(base.merge("format" => "csv"), { data: [{ "count" => 2 }, { "count" => 3 }] })
    expect(csv[:ctx][:serialized]).to include("count")
    expect(csv[:ctx][:serialized]).to include("2")

    toml = execute(base.merge("format" => "toml"), { data: { "count" => 2 } })
    expect(toml[:ctx][:serialized]).to include("count")
  end

  it "does not accept msgpack" do
    errors = generate(base.merge("format" => "msgpack")).validate_config(base.merge("format" => "msgpack"))
    expect(errors.map(&:code)).to include(:not_in_list)
  end
end
