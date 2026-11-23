# frozen_string_literal: true

require "rails_helper"

RSpec.describe "model-operation lookup scoping" do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:schema) do
    [{ "name" => "Amount", "name_slug" => "amount", "type" => "Types::Integer" }]
  end
  let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:other_entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

  def generate_and_run(generator_class, config, ctx)
    body = generator_class.new({ "config" => config }, {}).generate_body
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  def runtime_ctx(extra = {})
    Trailblazer::Context(
      {
        bound_entity: entity,
        customer_id: customer.id
      }.merge(extra)
    )
  end

  describe "clone_model" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::CloneModelGenerator }

    it "copies an already-loaded record and does not emit an EntityEntry lookup" do
      code = klass.new({ "config" => { "modelVariable" => "model", "resultVar" => "clone" } }, {}).generate_body
      expect(code).to include("FlowchartRuntime::Clone.copy(ctx[:model]")
      expect(code).not_to include("EntityEntry.build_for")
      expect(code).not_to include("EntityEntry.where")
      expect(code).not_to include("EntityEntry.find")
      expect(code).not_to include("FlowchartRuntime::Entries.scope")
    end
  end

  describe "batch_operation" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::BatchOperationGenerator }

    it "ANDs Entries.scope onto the source so the tenant predicate cannot be replaced" do
      code = klass.new({ "config" => { "sourceVariable" => "items", "operationType" => "find_each" } }, {}).generate_body
      expect(code).to include("FlowchartRuntime::Batch.run(ctx")
      expect(code).to include("source: ctx[:items]")
      expect(code).not_to include(".merge(")
    end

    it "does not destroy another entity's or tenant's rows even when the source relation is unscoped" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {})
      other_ent = create(:entity_entry, :with_data, entity: other_entity, customer: customer, entry_data: {})
      foreign = create(:entity_entry, customer: other_customer, entity: entity)
      ctx = runtime_ctx(items: EntityEntry.all)

      expect(generate_and_run(klass, { "sourceVariable" => "items", "operationType" => "destroy_all", "batchSize" => 100 }, ctx)).to eq(1)
      expect(EntityEntry.exists?(own.id)).to be(false)
      expect(EntityEntry.exists?(other_ent.id)).to be(true)
      expect(EntityEntry.exists?(foreign.id)).to be(true)
    end

    it "does not touch any row when the source relation filters to another customer" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {})
      foreign = create(:entity_entry, customer: other_customer, entity: entity)
      ctx = runtime_ctx(items: EntityEntry.where(customer_id: other_customer.id))

      expect(generate_and_run(klass, { "sourceVariable" => "items", "operationType" => "destroy_all", "batchSize" => 100 }, ctx)).to eq(0)
      expect(EntityEntry.exists?(own.id)).to be(true)
      expect(EntityEntry.exists?(foreign.id)).to be(true)
    end
  end

  describe "aggregate_query" do
    let(:klass) { CodeGenerators::ElementTypes::Process::ModelOperations::AggregateQueryGenerator }

    it "routes the lookup through QueryBuilder.for_entity with customer_id and bound entity" do
      code = klass.new(
        { "config" => { "resultVar" => "total", "aggregateFunction" => "count", "aggregateField" => "id" } },
        {}
      ).generate_body
      expect(code).to include("FlowchartRuntime::Entries.aggregate(ctx")
      expect(code).not_to include("EntityEntry.where")
    end

    it "counts only the bound entity's rows for this customer" do
      create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "amount" => 1 })
      create(:entity_entry, :with_data, entity: other_entity, customer: customer, entry_data: { "amount" => 1 })
      create(:entity_entry, :with_data, entity: entity, customer: other_customer, entry_data: { "amount" => 1 })
      ctx = runtime_ctx

      expect(generate_and_run(
        klass,
        { "resultVar" => "total", "aggregateFunction" => "count", "aggregateField" => "id" },
        ctx
      )).to eq(1)
      expect(ctx[:total]).to eq(1)
    end
  end
end
