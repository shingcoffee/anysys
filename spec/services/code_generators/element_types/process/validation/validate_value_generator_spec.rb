# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::ValidateValueGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "params.email", "rule" => "email", "resultVar" => "valid" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def errors(config)
    generate(config).validate_config(config)
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
        FlowchartRuntime::Step.attempt(
          ctx,
          :"validate_value.failed",
          FlowchartRuntime::ValueValidator::Error
        ) do
          check = FlowchartRuntime::ValueValidator.check(
            FlowchartRuntime::Step.dig(ctx[:params], :email),
            rule: "email"
          )
          ctx[:valid] = check[:valid]
          ctx[:normalized_value] = check[:normalized]
          unless check[:valid]
            return FlowchartRuntime::Step.fail(ctx, :"validate_value.email")
          end
          true
        end
      end
    RUBY
  end

  it "generates a flag step without failing" do
    src = generated_step(described_class.sample_input.merge("onInvalid" => "flag"))
    expect(src).not_to include("Step.fail")
    expect(src).to include("ctx[:valid] = check[:valid]")
  end

  it "emits a custom localized message and error field" do
    config = described_class.sample_input.merge(
      "errorField" => "email",
      "message" => { "en" => "Check the email.", "zh-CN" => "请核对邮箱。" }
    )
    src = generated_step(config)
    expect(src).to include("FlowchartRuntime::Step.fail_message(")
    expect(src).to include('field: "email"')
    expect(src).to include("Check the email.")
  end

  it "emits distinct source for every rule" do
    bodies = described_class::RULES.map do |rule|
      extra = case rule
      when "regex" then { "pattern" => "\\A.+\\z" }
      when "in_list" then { "allowedValues" => %w[active] }
      when "range" then { "minValue" => 0, "maxValue" => 10 }
      else {}
      end
      body(base.merge("rule" => rule).merge(extra))
    end
    expect(bodies.uniq.size).to eq(described_class::RULES.size)
  end

  describe "behaviour" do
    let(:params) { {} }
    let(:ctx) { { params: params, errors: [] } }

    it "accepts a valid email, normalises it, and fails an invalid email" do
      params["email"] = "Ada@Example.COM"
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:valid]).to be(true)
      expect(ctx[:normalized_value]).to eq("ada@example.com")

      bad = { params: { "email" => "nope" }, errors: [] }
      failed = execute(base, bad)
      expect(failed[:outcome]).to be(false)
      expect(bad[:errors]).to eq([I18n.t("flowchart_runtime.errors.validate_value.email")])
      expect(bad[:error_details].last["code"]).to eq("validate_value.email")
    end

    it "flags an invalid value without failing when onInvalid is flag" do
      ctx = { params: { "email" => "nope" }, errors: [] }
      result = execute(base.merge("onInvalid" => "flag"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:valid]).to be(false)
      expect(ctx[:errors]).to eq([])
    end

    it "uses a custom localized message and error field" do
      ctx = { params: { "email" => "nope" }, errors: [] }
      config = base.merge(
        "errorField" => "email",
        "message" => { "en" => "Check the email.", "zh-CN" => "请核对邮箱。" }
      )
      result = execute(config, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to eq(["Check the email."])
      expect(ctx[:error_details].last["field"]).to eq("email")
    end

    it "executes every rule against a concrete value" do
      fixtures = {
        "email" => ["user@example.test", { "sourceVariable" => "value" }],
        "phone" => ["+14155552671", { "sourceVariable" => "value" }],
        "url" => ["https://example.test", { "sourceVariable" => "value" }],
        "uuid" => ["550e8400-e29b-41d4-a716-446655440000", { "sourceVariable" => "value" }],
        "regex" => ["123", { "sourceVariable" => "value", "pattern" => "\\A\\d+\\z" }],
        "length" => ["ok", { "sourceVariable" => "value", "minLength" => 1, "maxLength" => 8 }],
        "range" => [5, { "sourceVariable" => "value", "minValue" => 0, "maxValue" => 10 }],
        "in_list" => ["active", { "sourceVariable" => "value", "allowedValues" => %w[active pending] }],
        "luhn" => ["4111111111111111", { "sourceVariable" => "value" }],
        "iban" => ["GB82WEST12345698765432", { "sourceVariable" => "value" }],
        "cn_resident_id" => ["110101199003078275", { "sourceVariable" => "value" }],
        "postal_code" => ["94105", { "sourceVariable" => "value", "postalCountry" => "US" }],
        "ip_address" => ["127.0.0.1", { "sourceVariable" => "value", "ipVersion" => "v4" }],
        "date" => ["2026-04-19", { "sourceVariable" => "value", "dateFormat" => "%Y-%m-%d" }],
        "date_range" => ["2026-04-19", { "sourceVariable" => "value", "minDate" => "2026-01-01", "maxDate" => "2026-12-31" }],
        "cn_mobile" => ["13812345678", { "sourceVariable" => "value" }],
        "required" => ["present", { "sourceVariable" => "value" }]
      }
      fixtures.each do |rule, (value, extra)|
        ctx = { value: value, errors: [] }
        config = described_class.sample_input.merge("rule" => rule).merge(extra)
        result = execute(config, ctx)
        expect(result[:outcome]).to be_truthy, "#{rule} failed: #{ctx[:errors].inspect}"
        expect(ctx[:valid]).to be(true), rule
      end

      { "any" => "::1", "v4" => "127.0.0.1", "v6" => "::1" }.each do |version, ip|
        ctx = { value: ip, errors: [] }
        result = execute(described_class.sample_input.merge(
          "rule" => "ip_address", "sourceVariable" => "value", "ipVersion" => version
        ), ctx)
        expect(result[:outcome]).to be_truthy, version
        expect(ctx[:valid]).to be(true)
      end
    end

    it "treats a blank source as valid when allowBlank is true" do
      ctx = { params: { "email" => "" }, errors: [] }
      result = execute(base.merge("allowBlank" => true), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:valid]).to be(true)
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable" do
      expect(errors({}).map(&:field)).to include("sourceVariable")
    end

    it "rejects an invalid pattern, range without bounds, empty list, and unknown postal country" do
      expect(errors(base.merge("rule" => "regex", "pattern" => "[")).map(&:code)).to include(:invalid_pattern)
      expect(errors(base.merge("rule" => "range")).map(&:code)).to include(:range_bound_required)
      expect(errors(base.merge("rule" => "in_list", "allowedValues" => [])).map(&:code)).to include(:empty_list)
      expect(errors(base.merge("rule" => "postal_code", "postalCountry" => "ZZ")).map(&:code))
        .to include(:unsupported_postal_country)
    end

    it "rejects a malformed errorField" do
      expect(errors(base.merge("errorField" => "not a field")).map(&:code)).to include(:invalid_identifier)
    end

    it "requires a date_range bound" do
      expect(errors(base.merge("rule" => "date_range")).map(&:code)).to include(:range_bound_required)
    end
  end
end
