# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator do
  let(:context) { {} }
  let(:element) { { "config" => {} } }

  it_behaves_like "a code generator"

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:models] = FlowchartRuntime::Entries.query(ctx).records
      end
    RUBY
  end

  it "fails when onEmpty is fail and emits offset and secondary sort" do
    expect(generated_step(described_class.sample_input.merge(
      "onEmpty" => "fail",
      "orderBy" => "status",
      "offset" => 3,
      "limit" => 10,
      "thenOrderBy" => "email",
      "thenOrderDirection" => "desc"
    ))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        query = FlowchartRuntime::Entries.query(
          ctx,
          order_by: "status",
          then_order_by: "email",
          then_order_direction: "desc",
          limit: 10,
          offset: 3
        )
        ctx[:models] = query.records
        return FlowchartRuntime::Step.fail(ctx, :"query_models.empty") unless query.records.present?
        query.records
      end
    RUBY
  end

  it "emits values mode with select" do
    expect(generated_step(described_class.sample_input.merge("returns" => "values", "select" => %w[email]))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:models] = FlowchartRuntime::Entries.query(
          ctx,
          select: ["email"],
          returns: "values"
        ).records
      end
    RUBY
  end

  it "emits another entity and own record scope" do
    expect(generated_step(described_class.sample_input.merge(
      "entity" => "Booking",
      "recordScope" => "own",
      "orderBy" => "created_at"
    ))).to include('entity: "Booking"', 'record_scope: "own"', 'order_by: "created_at"')
    expect(generated_step(described_class.sample_input.merge("entity" => "Booking"))).to include(
      "FlowchartRuntime::Step.attempt"
    )
  end

  it "emits pagination when pageSize is set" do
    expect(generated_step(described_class.sample_input.merge("pageSize" => 25, "orderBy" => "created_at"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        query = FlowchartRuntime::Entries.query(
          ctx,
          order_by: "created_at",
          page: ctx[:page],
          per_page: 25
        )
        ctx[:models] = query.records
        ctx[:pagination] = query.pagination
        query.records
      end
    RUBY
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:schema) do
      [
        { "name" => "Email", "name_slug" => "email", "type" => "Types::String" },
        { "name" => "Status", "name_slug" => "status", "type" => "Types::String" }
      ]
    end
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    def entry(customer:, data:)
      create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
    end

    it "returns this tenant's records and plucked values, never another tenant's row" do
      mine = entry(customer: customer, data: { "email" => "a@x.io", "status" => "active" })
      entry(customer: customer, data: { "email" => "b@x.io", "status" => "closed" })
      entry(customer: other, data: { "email" => "c@x.io", "status" => "active" })
      ctx = { bound_entity: entity, customer_id: customer.id }

      records = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "returns" => "records", "resultVar" => "models" },
        ctx: ctx
      )
      expect(records[:outcome].map(&:id)).to contain_exactly(mine.id, EntityEntry.where(customer_id: customer.id, entity_id: entity.id).where.not(id: mine.id).pick(:id))
      expect(records[:outcome].map(&:customer_id).uniq).to eq([customer.id])

      values_ctx = { bound_entity: entity, customer_id: customer.id }
      values = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "returns" => "values",
          "select" => %w[email],
          "resultVar" => "models",
          "conditions" => {
            "type" => "group",
            "joins" => [],
            "conditions" => [{ "type" => "single", "leftOperand" => "status", "operator" => "==", "rightOperand" => "active" }]
          }
        },
        ctx: values_ctx
      )
      expect(values[:outcome]).to eq(["a@x.io"])
      expect(values_ctx[:models]).to eq(["a@x.io"])
    end

    it "applies offset without leaking another tenant's row and fails on empty when asked" do
      first = entry(customer: customer, data: { "email" => "a@x.io", "status" => "active" })
      second = entry(customer: customer, data: { "email" => "b@x.io", "status" => "active" })
      entry(customer: other, data: { "email" => "c@x.io", "status" => "active" })
      ctx = { bound_entity: entity, customer_id: customer.id, errors: [] }
      rows = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "returns" => "records",
          "orderBy" => "email",
          "orderDirection" => "asc",
          "offset" => 1,
          "limit" => 10,
          "resultVar" => "models"
        },
        ctx: ctx
      )
      expect(rows[:outcome].map(&:id)).to eq([second.id])
      expect(rows[:outcome].map(&:id)).not_to include(first.id)

      empty = { bound_entity: entity, customer_id: customer.id, errors: [] }
      failed = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "returns" => "records",
          "onEmpty" => "fail",
          "conditions" => {
            "type" => "group",
            "joins" => [],
            "conditions" => [{ "type" => "single", "leftOperand" => "status", "operator" => "==", "rightOperand" => "missing" }]
          }
        },
        ctx: empty
      )
      expect(failed[:outcome]).to be(false)
      expect(empty[:errors]).to eq([I18n.t("flowchart_runtime.errors.query_models.empty")])
    end

    it "queries another reachable entity and compares a condition to a loaded record attribute" do
      other_schema = [
        { "name" => "Email", "name_slug" => "email", "type" => "Types::String" },
        { "name" => "Status", "name_slug" => "status", "type" => "Types::String" }
      ]
      bookings = create(:entity, customer: customer, name: "Booking", property_schema: other_schema.to_json)
      mine = create(:entity_entry, :with_data, entity: bookings, customer: customer, entry_data: { "email" => "a@x.io", "status" => "active" })
      create(:entity_entry, :with_data, entity: bookings, customer: customer, entry_data: { "email" => "b@x.io", "status" => "closed" })
      create(:entity_entry, :with_data, entity: bookings, customer: other, entry_data: { "email" => "c@x.io", "status" => "active" })
      source = entry(customer: customer, data: { "email" => "src@x.io", "status" => "active" })
      ctx = { bound_entity: entity, customer_id: customer.id, model: source }

      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "entity" => "Booking",
          "returns" => "records",
          "resultVar" => "models",
          "conditions" => {
            "type" => "group",
            "joins" => [],
            "conditions" => [{ "type" => "single", "leftOperand" => "status", "operator" => "==", "rightOperand" => "ctx.model.status" }]
          }
        },
        ctx: ctx
      )
      expect(result[:outcome].map(&:id)).to eq([mine.id])
      expect(ctx[:models].map(&:id)).to eq([mine.id])
    end
  end
end
