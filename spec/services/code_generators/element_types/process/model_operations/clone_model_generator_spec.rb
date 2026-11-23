# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::CloneModelGenerator do
  let(:element) { { "config" => { "modelVariable" => "model" } } }
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
        unless ctx[:model]
          return FlowchartRuntime::Step.fail(ctx, :record_missing, field: :modelVariable)
        end
        FlowchartRuntime::Step.attempt(
          ctx,
          :"clone_model.failed",
          FlowchartRuntime::Clone::Error,
          FlowchartRuntime::Entries::Error
        ) do
          ctx[:clone] = FlowchartRuntime::Clone.copy(ctx[:model])
        end
      end
    RUBY
  end

  it "is version 5.2.0" do
    expect(described_class._metadata[:version]).to eq("5.2.0")
  end

  it "passes exclude fields to Clone.copy" do
    code = generate("excludeFields" => ["email"])
    expect(code).to include('FlowchartRuntime::Clone.copy(ctx[:model], exclude: ["email"])')
  end

  it "applies override expressions onto the copy" do
    code = generate("overrides" => [{ "key" => "email", "value" => '"copy@x.io"' }])
    expect(code).to include('FlowchartRuntime::Entries.assign(copy, {"email" => "copy@x.io"}, strict: true)')
  end

  it "persists the copy through Entries.save when persist is true" do
    code = generate("persist" => true)
    expect(code).to include("return false unless FlowchartRuntime::Entries.save(ctx, copy)")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) { [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }] }
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    it "duplicates the loaded tenant record without persisting or touching another tenant" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      foreign = create(:entity_entry, :with_data, entity: entity, customer: other_customer, entry_data: { "email" => "z@x.io" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => own.id)
      ctx = { bound_entity: entity, customer_id: customer.id, model: model }

      expect(run_body({}, ctx)).to be_a(EntityEntry)
      expect(ctx[:clone]).not_to equal(model)
      expect(ctx[:clone]).not_to be_persisted
      expect(ctx[:clone].email).to eq("a@x.io")
      expect(foreign.reload.data_json["email"]).to eq("z@x.io")
    end

    it "fails the step instead of raising when no record was loaded" do
      ctx = { bound_entity: entity, customer_id: customer.id, model: nil, errors: [] }

      expect(run_body({}, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_missing")])
    end

    it "continues when onMissing is ignore and no record was loaded" do
      ctx = { bound_entity: entity, customer_id: customer.id, model: nil, errors: [] }

      expect(run_body({ "onMissing" => "ignore" }, ctx)).to be(true)
      expect(ctx[:clone]).to be_nil
      expect(ctx[:errors]).to eq([])
    end

    it "clears excluded fields, applies overrides, and persists a tenant-scoped copy" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      foreign = create(:entity_entry, :with_data, entity: entity, customer: other_customer, entry_data: { "email" => "z@x.io" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => own.id)
      ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }
      config = {
        "excludeFields" => ["email"],
        "overrides" => [{ "key" => "email", "value" => '"copy@x.io"' }],
        "persist" => true
      }

      expect(run_body(config, ctx)).to be_a(EntityEntry)
      expect(ctx[:clone]).to be_persisted
      expect(ctx[:clone].id).not_to eq(own.id)
      expect(ctx[:clone].customer_id).to eq(customer.id)
      expect(ctx[:clone].email).to eq("copy@x.io")
      expect(own.reload.email).to eq("a@x.io")
      expect(foreign.reload.data_json["email"]).to eq("z@x.io")
    end
  end
end
