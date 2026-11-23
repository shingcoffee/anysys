# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::ValidateContractGenerator do
  let(:element) { { "id" => "step_validate", "type" => "process", "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = {})
    described_class.new({ "id" => "step_validate", "type" => "process", "config" => config }, {}).generate_body
  end

  def errors_for(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  describe "schema" do
    it "has only :required errors for schema defaults" do
      schema = described_class._config_schema
      unexpected = errors_for(schema.defaults).reject { |error| error.code == :required }
      expect(unexpected).to eq([])
    end
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        return FlowchartRuntime::Step.fail(ctx, :contract_missing) unless ctx[:contract]
        ctx[:contract_valid] = ctx[:contract].validate(ctx[:params] || {})
      end
    RUBY
  end

  it "continues after an invalid contract when onInvalid is continue" do
    expect(generated_step(described_class.sample_input.merge("onInvalid" => "continue"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        return FlowchartRuntime::Step.fail(ctx, :contract_missing) unless ctx[:contract]
        ctx[:contract_valid] = ctx[:contract].validate(ctx[:params] || {})
        true
      end
    RUBY
  end

  describe "#generate_body" do
    it "uses the configured validVar" do
      expect(generate("validVar" => "ok")).to include("ctx[:ok] = ctx[:contract].validate(ctx[:params] || {})")
    end

    it "ignores a leftover contractRef" do
      expect(generate("contractRef" => "order_contract")).to include("ctx[:contract].validate(ctx[:params] || {})")
    end

    it "fails when ctx[:contract] is missing" do
      expect(generate).to include("return FlowchartRuntime::Step.fail(ctx, :contract_missing) unless ctx[:contract]")
    end
  end

  describe "#dependencies" do
    it "depends on :build_contract" do
      expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:build_contract])
    end
  end

  describe "behaviour" do
    def entity_with_required_name(customer)
      create(:entity, customer: customer, property_schema: [
        {
          "name" => "Name",
          "name_slug" => "name",
          "type" => "String",
          "html_type" => "text",
          "validators" => [{ "type" => "presence" }]
        }
      ].to_json)
    end

    it "returns the contract result and collects translated errors on ctx[:errors]" do
      customer_a = create(:customer)
      customer_b = create(:customer)
      entity_a = entity_with_required_name(customer_a)
      entity_b = entity_with_required_name(customer_b)
      entry_a = create(:entity_entry, entity: entity_a, customer: customer_a)
      create(:entity_entry, entity: entity_b, customer: customer_b)

      contract = EntityEntryContract.build_for(entity_a, audience: "admin").new(entry_a)
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: described_class.sample_input,
        ctx: {
          contract: contract,
          params: {},
          customer_id: customer_a.id,
          bound_entity: entity_a,
          audience: "admin"
        }
      )

      expect(result[:outcome]).to eq(false)
      expect(result[:ctx][:contract_valid]).to be(false)
      collected = FlowchartRuntime::Errors.collect(result[:ctx])
      expect(collected).to be_present
      expect(collected.join).to match(/can't be blank/i)
      expect(EntityEntry.where(customer_id: customer_b.id).count).to eq(1)
    end

    it "continues and records contract_valid false when onInvalid is continue" do
      customer = create(:customer)
      entity = entity_with_required_name(customer)
      entry = create(:entity_entry, entity: entity, customer: customer)
      contract = EntityEntryContract.build_for(entity, audience: "admin").new(entry)

      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "onInvalid" => "continue" },
        ctx: { contract: contract, params: {} }
      )

      expect(result[:outcome]).to eq(true)
      expect(result[:ctx][:contract_valid]).to be(false)
    end

    it "fails with contract_missing when no contract was built" do
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {},
        ctx: { params: { "name" => "Ada" }, errors: [] }
      )

      expect(result[:outcome]).to eq(false)
      expect(result[:ctx][:errors]).to eq([I18n.t("flowchart_runtime.errors.contract_missing")])
    end

    it "returns true when the contract accepts the params" do
      customer = create(:customer)
      entity = entity_with_required_name(customer)
      entry = create(:entity_entry, entity: entity, customer: customer)
      contract = EntityEntryContract.build_for(entity, audience: "admin").new(entry)

      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {},
        ctx: { contract: contract, params: { "name" => "Ada" } }
      )

      expect(result[:outcome]).to eq(true)
      expect(result[:ctx][:contract_valid]).to be(true)
      expect(FlowchartRuntime::Errors.collect(result[:ctx])).to eq([])
    end
  end
end
