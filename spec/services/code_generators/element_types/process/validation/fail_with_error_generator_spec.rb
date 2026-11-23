# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::FailWithErrorGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.fail_message(ctx, {"en" => "Not eligible", "zh-CN" => "不符合条件。"})
      end
    RUBY
  end

  it "emits a field when configured" do
    expect(generated_step(described_class.sample_input.merge("errorField" => "email"))).to include('field: "email"')
  end

  it "emits a custom error code and message variables" do
    src = generate(
      described_class.sample_input.merge(
        "errorCode" => "quota_exceeded",
        "messageVariables" => [{ "key" => "used", "value" => "ctx[:used]" }]
      )
    )
    expect(src).to include('code: "quota_exceeded"')
    expect(src).to include("variables:")
    expect(src).to include('"used" => ctx[:used]')
  end

  it "rejects a malformed field identifier" do
    codes = errors(described_class.sample_input.merge("errorField" => "not a field")).map(&:code)
    expect(codes).to include(:invalid_identifier)
  end

  it "rejects a malformed error code" do
    codes = errors(described_class.sample_input.merge("errorCode" => "Not Valid")).map(&:code)
    expect(codes).to include(:invalid_identifier)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    it "fails two tenant ctxs independently with locale fallback and field details" do
      ctx_a = { customer_id: customer.id, errors: [] }
      ctx_b = { customer_id: other.id, errors: [] }
      config = described_class.sample_input.merge(
        "message" => { "en" => "Not eligible", "zh-CN" => "不符合条件。" },
        "errorField" => "email"
      )

      I18n.with_locale(:"zh-CN") do
        result = execute(config, ctx_a)
        expect(result[:outcome]).to be(false)
      end
      expect(ctx_a[:errors]).to eq(["不符合条件。"])
      expect(ctx_a[:error_details].first).to include("field" => "email", "code" => "business_error")

      I18n.with_locale(:en) do
        execute(config, ctx_b)
      end
      expect(ctx_b[:errors]).to eq(["Not eligible"])
      expect(ctx_a[:errors]).to eq(["不符合条件。"])
    end

    it "interpolates message variables and records a custom error code" do
      ctx = { customer_id: customer.id, used: 3, errors: [] }
      config = described_class.sample_input.merge(
        "message" => { "en" => "Used %{used} already" },
        "errorCode" => "quota_exceeded",
        "messageVariables" => [{ "key" => "used", "value" => "ctx[:used]" }]
      )

      execute(config, ctx)
      expect(ctx[:errors]).to eq(["Used 3 already"])
      expect(ctx[:error_details].first["code"]).to eq("quota_exceeded")
    end
  end
end
