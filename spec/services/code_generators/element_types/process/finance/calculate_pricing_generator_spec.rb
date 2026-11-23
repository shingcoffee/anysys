# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Finance::CalculatePricingGenerator do
  let(:element) { { "config" => described_class.sample_input } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context)
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

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be_truthy, result.violations.inspect
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
    lint!(sample)
  end

  it "requires sourceVariable" do
    expect(errors({}).map(&:field)).to include("sourceVariable")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"calculate_pricing.failed",
          FlowchartRuntime::Pricing::Error
        ) do
          pricing = FlowchartRuntime::Pricing.calculate(
            ctx,
            lines: ctx[:line_items],
            quantity_field: "quantity",
            unit_price_field: "unit_price"
          )
          ctx[:pricing] = pricing
        end
      end
    RUBY
  end

  it "delegates to Pricing.calculate with line items" do
    code = body
    expect(code).to include("FlowchartRuntime::Pricing.calculate")
    expect(code).to include("ctx[:line_items]")
    expect(code).to include("quantity_field: \"quantity\"")
  end

  it "emits a percent discount" do
    expect(generated_step(described_class.sample_input.merge("discountType" => "percent", "discountValue" => 10)))
      .to include('discount_type: "percent"', "discount_value: 10.0")
  end

  it "emits a shipping override from a ctx variable" do
    expect(generated_step(described_class.sample_input.merge("shippingVariable" => "shipping")))
      .to include("shipping_override: ctx[:shipping]")
  end

  it "emits distinct source for every discount, tax, rounding, and round-per option" do
    {
      "discountType" => described_class::DISCOUNT_TYPES,
      "taxMode" => described_class::TAX_MODES,
      "roundingMode" => described_class::ROUNDING_MODES,
      "roundPer" => described_class::ROUND_PER
    }.each do |field, values|
      bodies = values.map { |value| body(described_class.sample_input.merge(field => value)) }
      expect(bodies.uniq.size).to eq(values.size), field
    end
  end

  describe "behaviour" do
    let(:items) { [{ "quantity" => 1, "unit_price" => "100" }] }

    it "totals exclusive tax from line items" do
      ctx = { line_items: items }
      result = execute(described_class.sample_input.merge("taxRate" => 10, "taxMode" => "exclusive"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:pricing]["total"]).to eq("110.00")
      expect(ctx[:pricing]["tax"]).to eq("10.00")
    end

    it "extracts inclusive tax" do
      ctx = { line_items: [{ "quantity" => 1, "unit_price" => "110" }] }
      result = execute(described_class.sample_input.merge("taxMode" => "inclusive", "taxRate" => 10), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:pricing]["lines"].first["net"]).to eq("100.00")
      expect(ctx[:pricing]["lines"].first["tax"]).to eq("10.00")
    end

    described_class::DISCOUNT_TYPES.each do |type|
      it "executes discountType #{type}" do
        ctx = { line_items: items, coupon_amount: 10 }
        config = described_class.sample_input.merge("discountType" => type, "discountValue" => 10)
        expect(execute(config, ctx)[:outcome]).to be_truthy
        expect(ctx[:pricing]).to be_a(Hash)
      end
    end

    described_class::TAX_MODES.each do |mode|
      it "executes taxMode #{mode}" do
        ctx = { line_items: items }
        config = described_class.sample_input.merge("taxMode" => mode, "taxRate" => 10)
        expect(execute(config, ctx)[:outcome]).to be_truthy
      end
    end

    described_class::ROUNDING_MODES.each do |mode|
      it "executes roundingMode #{mode}" do
        ctx = { line_items: [{ "quantity" => 1, "unit_price" => "1.225" }] }
        config = described_class.sample_input.merge("roundingMode" => mode, "precision" => 2)
        expect(execute(config, ctx)[:outcome]).to be_truthy
      end
    end

    described_class::ROUND_PER.each do |mode|
      it "executes roundPer #{mode}" do
        ctx = { line_items: items }
        expect(execute(described_class.sample_input.merge("roundPer" => mode), ctx)[:outcome]).to be_truthy
      end
    end

    it "uses shippingVariable over shippingAmount" do
      ctx = { line_items: items, shipping: "8.50" }
      config = described_class.sample_input.merge("shippingAmount" => 99, "shippingVariable" => "shipping")
      expect(execute(config, ctx)[:outcome]).to be_truthy
      expect(ctx[:pricing]["shipping"]).to eq("8.50")
    end

    it "fails with a translated message for a negative price" do
      ctx = { line_items: [{ "quantity" => 1, "unit_price" => "-3" }], errors: [] }
      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.calculate_pricing.invalid_line", line: 1))
    end
  end
end
