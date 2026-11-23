# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::UpdateModelGenerator do
  let(:element) { { "type" => "process", "config" => {} } }
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
        FlowchartRuntime::Step.attempt(ctx, :"update_model.failed", FlowchartRuntime::Entries::Error) do
          FlowchartRuntime::Entries.save(ctx, ctx[:model])
        end
      end
    RUBY
  end

  it "does not sync the contract or copy params by default" do
    code = generate
    expect(code).not_to include("ctx[:contract].sync")
    expect(code).not_to include("ctx[:params]")
    expect(code).to include("FlowchartRuntime::Entries.save(ctx, ctx[:model])")
  end

  it "copies params only when valuesFrom is params" do
    code = generate("valuesFrom" => "params")
    expect(code).to include("FlowchartRuntime::Entries.assign(ctx[:model], ctx[:params] || {})")
    expect(code).not_to include("ctx[:contract].sync")
  end

  it "syncs the contract only when valuesFrom is contract" do
    code = generate("valuesFrom" => "contract")
    expect(code).to include("ctx[:contract].sync")
    expect(code).to include("return FlowchartRuntime::Step.fail(ctx, :contract_missing) unless ctx[:contract]")
    expect(code).not_to include("ctx[:params]")
  end

  it "rejects contract or params when updating a record other than model" do
    expect(errors("modelVariable" => "cart", "valuesFrom" => "params").map(&:code)).to include(:page_record_only)
    expect(errors("modelVariable" => "cart", "valuesFrom" => "contract").map(&:code)).to include(:page_record_only)
    expect(errors("modelVariable" => "cart", "valuesFrom" => "assignments")).to eq([])
  end

  it "checks assignment keys against the page's entity only when updating the page's record" do
    entity = create(:entity, customer: create(:customer), property_schema: [
      { "name" => "Email", "name_slug" => "email", "html_type" => "email" }
    ].to_json)
    codes = ->(config) { described_class.new({ "config" => config }, { bound_entity: entity }).validate_config(config).map(&:code) }
    config = { "modelVariable" => "model", "assignments" => [{ "key" => "nickname", "value" => "'x'" }] }

    expect(codes.call(config)).to include(:unknown_attribute)
    expect(codes.call(config.merge("assignments" => [{ "key" => "email", "value" => "'x'" }]))).to eq([])
    expect(codes.call(config.merge("modelVariable" => "cart"))).to eq([])
  end

  it "is version 6.0.0" do
    expect(described_class._metadata[:version]).to eq("6.0.0")
  end

  it "skips an unchanged write only when skipIfUnchanged is set" do
    code = generate("skipIfUnchanged" => true)
    expect(code).to include("return true unless ctx[:model].has_changes_to_save?")
  end

  it "applies assignment expressions before saving" do
    code = generate("assignments" => [{ "key" => "email", "value" => '"n@x.io"' }])
    expect(code).to include('FlowchartRuntime::Entries.assign(ctx[:model], {"email" => "n@x.io"}, strict: true)')
    expect(code).not_to include("ctx[:contract].sync")
  end

  it "writes saved_changes when changesVar is set" do
    code = generate("changesVar" => "saved_changes")
    expect(code).to include("ctx[:saved_changes] = ctx[:model].saved_changes if saved")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) { [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }] }
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    def loaded(id)
      FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => id)
    end

    it "does not mass-assign params or re-sync a leftover contract by default" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      contract = EntityEntryContract.build_for(entity).new(own)
      contract.validate("email" => "from-contract@x.io")
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: loaded(own.id),
        contract: contract,
        params: { "email" => "from-params@x.io" },
        errors: []
      }

      expect(run_body({ "assignments" => [{ "key" => "email", "value" => '"n@x.io"' }] }, ctx)).to be(true)
      expect(own.reload.email).to eq("n@x.io")
    end

    it "updates the tenant row from params when valuesFrom is params and ignores internal columns" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: loaded(own.id),
        params: { "email" => "n@x.io", "customer_id" => other_customer.id, "id" => 0 },
        errors: []
      }

      expect(run_body({ "modelVariable" => "model", "valuesFrom" => "params" }, ctx)).to be(true)
      expect(own.reload.email).to eq("n@x.io")
      expect(own.customer_id).to eq(customer.id)
    end

    it "captures saved_changes when changesVar is set" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: loaded(own.id),
        params: { "email" => "n@x.io" },
        errors: []
      }

      expect(run_body({ "valuesFrom" => "params", "changesVar" => "saved_changes" }, ctx)).to be(true)
      expect(ctx[:saved_changes]).to be_present
    end

    it "skips the write when skipIfUnchanged and nothing changed" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      model = loaded(own.id)
      stamp = own.updated_at
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: model,
        params: { "email" => "a@x.io" },
        errors: []
      }

      expect(run_body({ "valuesFrom" => "params", "skipIfUnchanged" => true }, ctx)).to be(true)
      expect(own.reload.updated_at).to eq(stamp)
    end

    it "applies assignments then saves this tenant's row only" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      foreign = create(:entity_entry, :with_data, entity: entity, customer: other_customer, entry_data: { "email" => "z@x.io" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: loaded(own.id),
        params: { "email" => "from-params@x.io" },
        errors: []
      }
      config = { "assignments" => [{ "key" => "email", "value" => '"n@x.io"' }] }

      expect(run_body(config, ctx)).to be(true)
      expect(own.reload.email).to eq("n@x.io")
      expect(foreign.reload.data_json["email"]).to eq("z@x.io")
    end

    it "fails with record_missing when the record variable is empty" do
      ctx = { bound_entity: entity, customer_id: customer.id, model: nil, errors: [] }

      expect(run_body({}, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_missing")])
    end
  end
end
