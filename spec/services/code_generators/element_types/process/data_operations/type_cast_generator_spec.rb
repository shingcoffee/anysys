# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::TypeCastGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "raw_value", "targetType" => "integer", "resultVar" => "parsed" }
  end
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"type_cast.failed", FlowchartRuntime::Cast::Error) do
          ctx[:cast_value] = FlowchartRuntime::Cast.apply(ctx[:amount], type: "string")
          true
        end
      end
    RUBY
  end

  it "emits on_error variants" do
    expect(generated_step(described_class.sample_input.merge("targetType" => "date", "onError" => "nil")))
      .to include('on_error: "nil"')
    default_code = generated_step(
      described_class.sample_input.merge("targetType" => "date", "onError" => "default", "defaultValue" => "1970-01-01")
    )
    expect(default_code).to include('on_error: "default"')
    expect(default_code).to include('default_value: "1970-01-01"')
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean body for every targetType" do
    described_class::TARGET_TYPES.each do |type|
      config = described_class.sample_input.merge("targetType" => type)
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[cast_value])
      expect(result.ok?).to be(true), "#{type}: #{result.violations.inspect}"
    end
  end

  it "emits distinct code for every targetType" do
    bodies = described_class::TARGET_TYPES.map { |type| body(base.merge("targetType" => type)) }
    expect(bodies.uniq.size).to eq(described_class::TARGET_TYPES.size)
  end

  describe "behaviour" do
    it "casts an integer" do
      ctx = { raw_value: "42" }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:parsed]).to eq(42)
    end

    it "does not silently turn abc into 0" do
      ctx = { raw_value: "abc" }
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not cast the value")
    end

    it "casts a decimal" do
      ctx = { raw_value: "19.50" }
      execute(base.merge("targetType" => "decimal"), ctx)
      expect(ctx[:parsed]).to eq(BigDecimal("19.50"))
    end

    it "records a translated failure for an unparsable date" do
      ctx = { raw_value: "nope" }
      result = execute(base.merge("targetType" => "date"), ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not cast the value")
    end

    it "returns nil on a failed cast when onError is nil" do
      ctx = { raw_value: "nope" }
      result = execute(base.merge("targetType" => "date", "onError" => "nil"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:parsed]).to be_nil
    end

    it "returns defaultValue on a failed cast when onError is default" do
      ctx = { raw_value: "nope" }
      result = execute(base.merge("targetType" => "date", "onError" => "default", "defaultValue" => "1970-01-01"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:parsed]).to eq("1970-01-01")
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable" do
      expect(errors({}).map(&:field)).to include("sourceVariable")
    end

    it "rejects an invalid targetType" do
      expect(errors("sourceVariable" => "x", "targetType" => "invalid").map(&:code)).to include(:not_in_list)
    end

    it "rejects exotic programmer types" do
      %w[symbol complex rational time date_time json hash float].each do |type|
        expect(errors("sourceVariable" => "x", "targetType" => type).map(&:code)).to include(:not_in_list)
      end
    end
  end
end
