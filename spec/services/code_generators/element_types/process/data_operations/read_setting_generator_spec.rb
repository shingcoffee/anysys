# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::ReadSettingGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"read_setting.failed",
          FlowchartRuntime::Constants::Error
        ) do
          ctx[:constant_options] = FlowchartRuntime::Constants.options(ctx, "1")
          true
        end
      end
    RUBY
  end

  it "generates a label lookup without a nil default kwarg" do
    config = described_class.sample_input.merge("returns" => "label", "value" => "ctx[:params][:status]")
    expect(generated_step(config)).to include("FlowchartRuntime::Constants.label(ctx,")
    expect(generated_step(config)).to include("ctx[:params][:status]")
    expect(generated_step(config)).not_to include("default:")
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "emits a BodyLint-clean body for each returns variant" do
    %w[options label].each do |returns|
      config = described_class.sample_input.merge("returns" => returns)
      next if errors(config).any?

      code = generate(config)
      expect(CodeGenerators::BodyLint.check(code, outputs: %w[constant_options]).ok?).to be(true), code
    end
  end

  it "requires value when returning a label" do
    config = described_class.sample_input.merge("returns" => "label", "value" => nil)
    expect(errors(config).map(&:code)).to include(:required)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:shared) { create(:constant, :shared, options: %w[Open Closed]) }

    before do
      ConstantCustomerOverride.create!(constant: shared, customer_id: customer.id, options: %w[Draft Live])
    end

    it "returns the customer override and the other tenant's global default" do
      own = { customer_id: customer.id, errors: [] }
      expect(CodeGenerators::TestRunner.execute(described_class, config: { "constant" => shared.id, "returns" => "options" }, ctx: own)[:outcome]).to be(true)
      expect(own[:constant_options]).to eq(%w[Draft Live])

      foreign = { customer_id: other.id, errors: [] }
      expect(CodeGenerators::TestRunner.execute(described_class, config: { "constant" => shared.id, "returns" => "options" }, ctx: foreign)[:outcome]).to be(true)
      expect(foreign[:constant_options]).to eq(%w[Open Closed])
    end

    it "reads a constant by name" do
      ctx = { customer_id: customer.id, errors: [] }
      expect(CodeGenerators::TestRunner.execute(described_class, config: { "constant" => shared.name, "returns" => "options" }, ctx: ctx)[:outcome]).to be(true)
      expect(ctx[:constant_options]).to eq(%w[Draft Live])
    end

    it "returns the label for a value from the customer override" do
      ctx = { customer_id: customer.id, params: { "status" => "Draft" }, errors: [] }
      config = { "constant" => shared.id, "returns" => "label", "value" => "ctx[:params][\"status\"]" }
      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)[:outcome]).to be(true)
      expect(ctx[:constant_options]).to eq("Draft")
    end

    it "fails with a translated message when the constant is another tenant's" do
      owned = create(:constant, :customer_specific, customer: other, options: %w[A])
      ctx = { customer_id: customer.id, errors: [] }
      expect(CodeGenerators::TestRunner.execute(described_class, config: { "constant" => owned.id, "returns" => "options" }, ctx: ctx)[:outcome]).to be(false)
      expect(ctx[:errors].first).to include(I18n.t("flowchart_runtime.errors.read_setting.failed", reason: "Error"))
    end

    it "returns defaultValue when the option is missing from this customer's list" do
      ctx = { customer_id: customer.id, params: { "status" => "Missing" }, errors: [] }
      config = {
        "constant" => shared.id,
        "returns" => "label",
        "value" => "ctx[:params][\"status\"]",
        "defaultValue" => '"Unknown"'
      }
      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)[:outcome]).to be(true)
      expect(ctx[:constant_options]).to eq("Unknown")
    end
  end
end
