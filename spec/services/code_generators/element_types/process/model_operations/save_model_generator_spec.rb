# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::SaveModelGenerator do
  let(:element) { { "id" => "step_save", "type" => "process", "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def run_body(config, ctx)
    body = generate(config)
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        return FlowchartRuntime::Step.fail(ctx, :contract_missing) unless ctx[:contract]
        FlowchartRuntime::Step.attempt(ctx, :"save_model.failed", FlowchartRuntime::Entries::Error) do
          FlowchartRuntime::Entries.save(ctx, ctx[:contract])
        end
      end
    RUBY
  end

  it "is version 5.2.0" do
    expect(described_class._metadata[:version]).to eq("5.2.0")
  end

  it "continues after a failed save when onInvalid is continue" do
    code = generate("onInvalid" => "continue")
    expect(code).to include("FlowchartRuntime::Entries.save(ctx, ctx[:contract]) || true")
  end

  it "records savedVar from the save result" do
    code = generate("savedVar" => "saved")
    expect(code).to include("saved = FlowchartRuntime::Entries.save(ctx, ctx[:contract])")
    expect(code).to include("ctx[:saved] = saved")
  end

  it "fails when ctx[:contract] is missing" do
    code = generate
    expect(code).to include("return FlowchartRuntime::Step.fail(ctx, :contract_missing) unless ctx[:contract]")
  end

  it "keeps the validate_contract dependency" do
    expect(described_class.new({ "config" => {} }, {}).dependencies).to eq([:validate_contract])
  end

  it "ignores a leftover contractRef" do
    expect(generate("contractRef" => "order_contract")).to include("FlowchartRuntime::Entries.save(ctx, ctx[:contract])")
    expect(generate("contractRef" => "order_contract")).not_to include("order_contract")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) { [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }] }
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    it "persists the contract model for this tenant only" do
      entry = FlowchartRuntime::Entries.scope({ bound_entity: entity, customer_id: customer.id })
                .new(customer_id: customer.id, entity_id: entity.id)
      contract = EntityEntryContract.build_for(entity).new(entry)
      expect(contract.validate("email" => "a@x.io")).to be(true)
      ctx = { bound_entity: entity, customer_id: customer.id, contract: contract, model: entry, errors: [] }

      expect(run_body({}, ctx)).to be(true)
      expect(entry).to be_persisted
      expect(entry.reload.email).to eq("a@x.io")
      expect(entry.customer_id).to eq(customer.id)
    end

    it "refuses to save another tenant's row" do
      foreign = create(:entity_entry, :with_data, entity: entity, customer: other_customer,
                       entry_data: { "email" => "z@x.io" })
      contract = EntityEntryContract.build_for(entity).new(foreign)
      ctx = { bound_entity: entity, customer_id: customer.id, contract: contract, model: foreign, errors: [] }

      expect(run_body({}, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.save_model.failed", reason: "Error")])
      expect(foreign.reload.data_json["email"]).to eq("z@x.io")
    end

    it "fails with contract_missing when no contract was built" do
      ctx = { bound_entity: entity, customer_id: customer.id, errors: [] }

      expect(run_body({}, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.contract_missing")])
    end

    it "records savedVar and continues when onInvalid is continue" do
      entry = FlowchartRuntime::Entries.scope({ bound_entity: entity, customer_id: customer.id })
                .new(customer_id: customer.id, entity_id: entity.id)
      contract = EntityEntryContract.build_for(entity).new(entry)
      expect(contract.validate("email" => "a@x.io")).to be(true)
      ctx = { bound_entity: entity, customer_id: customer.id, contract: contract, model: entry, errors: [] }

      expect(run_body({ "onInvalid" => "continue", "savedVar" => "saved" }, ctx)).to be(true)
      expect(ctx[:saved]).to be(true)
      expect(entry).to be_persisted
      expect(entry.customer_id).to eq(customer.id)
    end
  end
end
