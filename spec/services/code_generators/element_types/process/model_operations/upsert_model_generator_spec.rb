# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::UpsertModelGenerator do
  let(:element) { { "type" => "process", "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def match_email(from = "ctx[:params][:email]")
    [{ "key" => "email", "value" => from }]
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
    expect(unexpected.map(&:code)).to eq([])
    expect(errors(defaults).map(&:code)).to eq([:required])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"upsert_model.failed", FlowchartRuntime::Entries::Error) do
          record, created = FlowchartRuntime::Entries.upsert(
            ctx,
            match: {"email" => ctx[:params][:email]},
            attributes: {}
          )
          return false unless record
          ctx[:model] = record
          ctx[:created] = created
          record
        end
      end
    RUBY
  end

  it "is version 6.0.0" do
    expect(described_class._metadata[:version]).to eq("6.0.0")
  end

  it "does not mass-assign params when valuesFrom is assignments" do
    code = generate("matchFields" => match_email, "assignments" => [{ "key" => "status", "value" => '"ok"' }])
    expect(code).to include('attributes: {"status" => "ok"}')
    expect(code).not_to include("ctx[:params].to_h.merge")
  end

  it "merges assignment expressions onto params when valuesFrom is params" do
    code = generate("matchFields" => match_email, "valuesFrom" => "params",
                    "assignments" => [{ "key" => "status", "value" => '"ok"' }])
    expect(code).to include('attributes: (ctx[:params] || {}).to_h.merge({"status" => "ok"})')
  end

  it "emits distinct onMatch branches" do
    update = generate("matchFields" => match_email, "onMatch" => "update")
    skip = generate("matchFields" => match_email, "onMatch" => "skip")
    fail_code = generate("matchFields" => match_email, "onMatch" => "fail")
    expect(update).not_to include("on_match:")
    expect(skip).to include('on_match: "skip"')
    expect(fail_code).to include('on_match: "fail"')
    expect([update, skip, fail_code].uniq.size).to eq(3)
  end

  it "rejects an empty matchFields list" do
    expect(errors("matchFields" => []).map(&:code)).to include(:required)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) do
      [
        { "name" => "Email", "name_slug" => "email", "data_type" => "string" },
        { "name" => "Status", "name_slug" => "status", "data_type" => "string" }
      ]
    end
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "creates a tenant row then updates it, never writing another tenant's row" do
      create(:entity_entry, :with_data, entity: entity, customer: other_customer,
             entry_data: { "email" => "a@x.io", "status" => "theirs" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        params: { "email" => "a@x.io", "status" => "mine" }.with_indifferent_access,
        errors: []
      }
      config = { "matchFields" => match_email, "valuesFrom" => "params" }

      expect(run_body(config, ctx)).to be_truthy
      expect(ctx[:created]).to be(true)
      expect(ctx[:model].email).to eq("a@x.io")
      expect(ctx[:model].status).to eq("mine")
      expect(ctx[:model].customer_id).to eq(customer.id)

      second = ctx.merge(params: { "email" => "a@x.io", "status" => "ok" }.with_indifferent_access, errors: [])
      expect(run_body(config, second)).to be_truthy
      expect(second[:created]).to be(false)
      expect(second[:model].id).to eq(ctx[:model].id)
      expect(second[:model].reload.status).to eq("ok")
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(1)
    end

    it "skips the write when onMatch is skip and a tenant row already matches" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer,
                   entry_data: { "email" => "a@x.io", "status" => "old" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        params: { "email" => "a@x.io", "status" => "hijacked" }.with_indifferent_access,
        errors: []
      }
      config = { "matchFields" => match_email, "valuesFrom" => "params", "onMatch" => "skip" }

      expect(run_body(config, ctx)).to be_truthy
      expect(ctx[:created]).to be(false)
      expect(ctx[:model].id).to eq(own.id)
      expect(own.reload.status).to eq("old")
    end

    it "fails when onMatch is fail and a tenant row already matches" do
      create(:entity_entry, :with_data, entity: entity, customer: customer,
             entry_data: { "email" => "a@x.io", "status" => "old" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        params: { "email" => "a@x.io", "status" => "hijacked" }.with_indifferent_access,
        errors: []
      }
      config = { "matchFields" => match_email, "onMatch" => "fail" }

      expect(run_body(config, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_already_exists")])
    end

    it "writes assignment values onto a newly created tenant row without copying params" do
      create(:entity_entry, :with_data, entity: entity, customer: other_customer,
             entry_data: { "email" => "a@x.io", "status" => "theirs" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        params: { "email" => "a@x.io", "status" => "from-params" }.with_indifferent_access,
        errors: []
      }
      config = {
        "matchFields" => match_email,
        "assignments" => [{ "key" => "status", "value" => '"mine"' }]
      }

      expect(run_body(config, ctx)).to be_truthy
      expect(ctx[:created]).to be(true)
      expect(ctx[:model].status).to eq("mine")
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(1)
    end
  end
end
