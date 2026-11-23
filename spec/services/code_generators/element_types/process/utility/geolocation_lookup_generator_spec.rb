# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::GeolocationLookupGenerator do
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
    result = CodeGenerators::BodyLint.check(body(sample), outputs: %w[location])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"geolocation_lookup.failed",
          FlowchartRuntime::Geolocation::Error
        ) do
          location = FlowchartRuntime::Geolocation.lookup(
            ctx,
            source: ctx[:origin],
            other: ctx[:destination]
          )
          ctx[:location] = location
          location != false
        end
      end
    RUBY
  end

  it "does not offer Google or Mapbox providers" do
    names = described_class._config_schema.fields.map(&:name)
    expect(names).not_to include("provider", "fallbackProvider", "mode", "lookupKey")
  end

  it "requires otherVariable" do
    expect(errors(described_class.sample_input.except("otherVariable")).map(&:code)).to include(:required)
  end

  it "emits a BodyLint-clean body without HTTP" do
    expect(body).to include("FlowchartRuntime::Geolocation.lookup")
    expect(body).not_to include("OutboundHttp")
    expect(CodeGenerators::BodyLint.check(body, outputs: %w[location]).ok?).to be(true)
  end

  describe "behaviour" do
    it "computes Haversine distance without HTTP" do
      expect(OutboundHttp).not_to receive(:request)
      result = execute(
        described_class.sample_input,
        { origin: { lat: 0, lng: 0 }, destination: { lat: 0, lng: 1 } }
      )
      expect(result[:outcome]).to be(true)
      expect(result[:ctx][:location][:km]).to be > 100
    end

    it "fails when a coordinate is missing" do
      result = execute(described_class.sample_input, { origin: { lat: 0 }, destination: { lat: 0, lng: 1 }, errors: [] })
      expect(result[:outcome]).to be(false)
      expect(result[:ctx][:errors]).to include(I18n.t("flowchart_runtime.errors.geolocation_lookup.invalid_coordinates"))
    end
  end
end
