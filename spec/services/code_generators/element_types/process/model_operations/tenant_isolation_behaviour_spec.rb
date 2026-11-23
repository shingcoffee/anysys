# frozen_string_literal: true

require "rails_helper"

RSpec.describe "model-operation tenant isolation" do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:schema) do
    [
      { "name" => "Email", "name_slug" => "email", "type" => "Types::String" },
      { "name" => "Status", "name_slug" => "status", "type" => "Types::String" }
    ]
  end
  let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:other_entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

  def entry_for(entity:, customer:, data:)
    create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
  end

  def runtime_ctx(extra = {})
    params = extra.delete(:params) || {}
    Trailblazer::Context(
      {
        params: params.with_indifferent_access,
        bound_entity: entity,
        customer_id: customer.id
      }.merge(extra)
    )
  end

  def generate_and_run(generator_class, config, ctx)
    name = generator_class.generator_name
    body = generator_class.new({ "action" => name, "config" => config }, {}).generate_body
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  describe "find_model" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::FindModelGenerator }
    let(:cfg) { { "findBy" => "id", "idSource" => "params.id", "resultVar" => "model" } }

    it "does not load another customer's entry and returns false" do
      own = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      foreign = create(:entity_entry, customer: other_customer, entity: entity)
      ctx = runtime_ctx(params: { "id" => foreign.id })

      expect(generate_and_run(klass, cfg, ctx)).to be(false)
      expect(ctx[:model]).to be_nil
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])

      ctx_own = runtime_ctx(params: { "id" => own.id })
      expect(generate_and_run(klass, cfg, ctx_own)).to be(true)
      expect(ctx_own[:model]).to be_a(EntityEntry)
      expect(ctx_own[:model].id).to eq(own.id)
    end

    it "validates the Task 5 find_model config" do
      expect(klass.new({ "config" => cfg }, {}).validate_config(cfg)).to be_empty
    end
  end

  describe "upsert_model" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::UpsertModelGenerator }
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "creates a new own entry when matching another customer's id" do
      foreign = create(:entity_entry, :with_data, customer: other_customer, entity: entity,
                       entry_data: { "email" => "f@x.io" })
      ctx = runtime_ctx(id: foreign.id, params: { "email" => "n@x.io" })
      count = EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count

      expect(generate_and_run(klass, {
        "matchFields" => [{ "key" => "id", "value" => "ctx[:id]" }],
        "valuesFrom" => "params"
      }, ctx)).to be_truthy

      expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(count + 1)
      expect(ctx[:model]).to be_persisted
      expect(ctx[:model].id).not_to eq(foreign.id)
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(ctx[:model].email).to eq("n@x.io")
      expect(foreign.reload.customer_id).to eq(other_customer.id)
    end

    it "updates the own entry whose data.email matches" do
      own = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "old" })
      entry_for(entity: entity, customer: customer, data: { "email" => "z@x.io", "status" => "other" })
      ctx = runtime_ctx(email: "a@x.io", params: { "email" => "a@x.io", "status" => "new" })

      expect(generate_and_run(klass, {
        "matchFields" => [{ "key" => "email", "value" => "ctx[:params][:email]" }],
        "valuesFrom" => "params"
      }, ctx)).to be_truthy

      expect(ctx[:model].id).to eq(own.id)
      expect(ctx[:model].reload.status).to eq("new")
      expect(ctx[:model].email).to eq("a@x.io")
    end

    it "never finds or restamps a foreign row sharing an id or email" do
      foreign = create(:entity_entry, :with_data, customer: other_customer, entity: entity,
                       entry_data: { "email" => "shared@x.io", "status" => "foreign" })
      snapshot = foreign.attributes.slice("id", "customer_id", "entity_id", "data")
      ctx = runtime_ctx(
        id: foreign.id,
        email: "shared@x.io",
        params: {
          "email" => "shared@x.io",
          "status" => "hijacked",
          "id" => foreign.id,
          "customer_id" => other_customer.id,
          "entity_id" => 0,
          "data" => { "email" => "x" }.to_json
        }
      )
      own_count = EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count

      expect(generate_and_run(klass, {
        "matchFields" => [{ "key" => "email", "value" => "ctx[:params][:email]" }],
        "valuesFrom" => "params"
      }, ctx)).to be_truthy

      foreign.reload
      expect(foreign.attributes.slice("id", "customer_id", "entity_id", "data")).to eq(snapshot)
      expect(ctx[:model].id).not_to eq(foreign.id)
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(ctx[:model].entity_id).to eq(entity.id)
      expect(ctx[:model].email).to eq("shared@x.io")
      expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(own_count + 1)
    end

    it "ignores internal-column keys in params" do
      own = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "old" })
      ctx = runtime_ctx(
        email: "a@x.io",
        params: {
          "email" => "a@x.io",
          "status" => "new",
          "id" => 0,
          "customer_id" => other_customer.id,
          "entity_id" => 0,
          "data" => "{}"
        }
      )

      expect(generate_and_run(klass, {
        "matchFields" => [{ "key" => "email", "value" => "ctx[:params][:email]" }],
        "valuesFrom" => "params"
      }, ctx)).to be_truthy

      own.reload
      expect(own.id).to eq(ctx[:model].id)
      expect(own.customer_id).to eq(customer.id)
      expect(own.entity_id).to eq(entity.id)
      expect(own.email).to eq("a@x.io")
      expect(own.status).to eq("new")
    end
  end

  describe "bulk_import" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::BulkImportGenerator }

    def run_import(on_dup, rows)
      ctx = runtime_ctx(records: rows)
      expect(generate_and_run(
        klass,
        { "sourceVariable" => "records", "resultVar" => "import_result", "onDuplicateKey" => on_dup,
          "uniqueBy" => %w[email] },
        ctx
      )).to be_truthy
      ctx
    end

    %w[skip update].each do |on_dup|
      it "never finds, updates, or restamps a foreign row for onDuplicateKey=#{on_dup}" do
        foreign = create(:entity_entry, :with_data, customer: other_customer, entity: entity,
                         entry_data: { "email" => "shared@x.io", "status" => "foreign" })
        snapshot = foreign.attributes.slice("id", "customer_id", "entity_id", "data")
        other_ent = entry_for(entity: other_entity, customer: customer,
                              data: { "email" => "shared@x.io", "status" => "other-entity" })
        other_snapshot = other_ent.attributes.slice("id", "customer_id", "entity_id", "data")
        ctx = run_import(on_dup, [{
          "id" => foreign.id,
          "email" => "shared@x.io",
          "status" => "hijacked",
          "customer_id" => other_customer.id,
          "entity_id" => 0,
          "data" => { "email" => "x" }.to_json
        }])

        foreign.reload
        other_ent.reload
        expect(foreign.attributes.slice("id", "customer_id", "entity_id", "data")).to eq(snapshot)
        expect(other_ent.attributes.slice("id", "customer_id", "entity_id", "data")).to eq(other_snapshot)
        expect(ctx[:import_result][:failed]).to eq(0)
        created = EntityEntry.where(customer_id: customer.id, entity_id: entity.id)
        expect(created.count).to eq(1)
        expect(created.first.id).not_to eq(foreign.id)
        expect(created.first.email).to eq("shared@x.io")
        expect(created.first.customer_id).to eq(customer.id)
        expect(created.first.entity_id).to eq(entity.id)
      end
    end

    it "updates only the bound entity's matching row and ignores internal columns on the row hash" do
      own = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "old" })
      ctx = run_import("update", [{
        "id" => 0,
        "email" => "a@x.io",
        "status" => "new",
        "customer_id" => other_customer.id,
        "entity_id" => 0,
        "data" => "{}"
      }])

      own.reload
      expect(own.id).to eq(own.id)
      expect(own.customer_id).to eq(customer.id)
      expect(own.entity_id).to eq(entity.id)
      expect(own.email).to eq("a@x.io")
      expect(own.status).to eq("new")
      expect(ctx[:import_result]).to include(created: 0, updated: 1, skipped: 0, failed: 0)
    end

    it "commits other rows when one row fails inside a nested savepoint" do
      boom = Object.new
      def boom.to_h
        raise StandardError, "row exploded"
      end
      ctx = runtime_ctx(records: [
        { "email" => "ok1@x.io", "status" => "a" },
        boom,
        { "email" => "ok2@x.io", "status" => "b" }
      ])

      expect(generate_and_run(
        klass,
        { "sourceVariable" => "records", "resultVar" => "import_result", "onDuplicateKey" => "skip",
          "uniqueBy" => %w[email] },
        ctx
      )).to be_truthy

      emails = EntityEntry.where(customer_id: customer.id, entity_id: entity.id).map(&:email)
      expect(emails).to contain_exactly("ok1@x.io", "ok2@x.io")
      expect(ctx[:import_result]).to include(created: 2, updated: 0, skipped: 0, failed: 1)
      expect(ctx[:import_result][:errors]).to include(hash_including(index: 1, message: "row exploded"))
    end

    it "fails before any write when the row list exceeds MAX_ROWS" do
      rows = Array.new(CodeGenerators::ElementTypes::Process::ModelOperations::BulkImportGenerator::MAX_ROWS + 1) do |i|
        { "email" => "u#{i}@x.io" }
      end
      ctx = runtime_ctx(records: rows)

      expect(generate_and_run(
        klass,
        { "sourceVariable" => "records", "resultVar" => "import_result", "onDuplicateKey" => "skip" },
        ctx
      )).to be(false)

      expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(0)
      expect(ctx[:errors]).to include(
        I18n.t(
          "flowchart_runtime.errors.bulk_import.too_many_rows",
          count: rows.size,
          max: CodeGenerators::ElementTypes::Process::ModelOperations::BulkImportGenerator::MAX_ROWS
        )
      )
    end
  end

  describe "update_model" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::UpdateModelGenerator }

    it "updates email only for a contract-less save and ignores internal columns" do
      own = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      ctx = runtime_ctx(
        model: EntityEntry.build_for(entity).find(own.id),
        params: { "email" => "n@x.io", "customer_id" => other_customer.id, "entity_id" => 0, "id" => 0 }
      )

      expect(generate_and_run(klass, { "modelVariable" => "model", "valuesFrom" => "params" }, ctx)).to be_truthy

      own.reload
      expect(own.email).to eq("n@x.io")
      expect(own.customer_id).to eq(customer.id)
      expect(own.entity_id).to eq(entity.id)
      expect(own.id).to eq(ctx[:model].id)
    end
  end

  describe "check_existence / count_records" do
    let(:own) { entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" }) }

    before do
      own
      entry_for(entity: other_entity, customer: customer, data: { "email" => "b@x.io" })
      create(:entity_entry, :with_data, customer: other_customer, entity: entity,
             entry_data: { "email" => "c@x.io" })
    end

    it "count_records resultAs exists ignores other customers' and other entities' rows" do
      klass = CodeGenerators::ElementTypes::Process::ModelOperations::CountRecordsGenerator
      ctx = runtime_ctx
      expect(generate_and_run(klass, { "resultVar" => "exists", "resultAs" => "exists" }, ctx)).to be(true)
      expect(ctx[:exists]).to be(true)

      empty_ctx = runtime_ctx
      EntityEntry.where(id: own.id).delete_all
      expect(generate_and_run(klass, { "resultVar" => "exists", "resultAs" => "exists" }, empty_ctx)).to be(false)
      expect(empty_ctx[:exists]).to be(false)
    end

    it "count_records ignores other customers' and other entities' rows" do
      klass = CodeGenerators::ElementTypes::Process::ModelOperations::CountRecordsGenerator
      ctx = runtime_ctx
      expect(generate_and_run(klass, { "resultVar" => "count" }, ctx)).to eq(1)
      expect(ctx[:count]).to eq(1)
    end
  end
end
