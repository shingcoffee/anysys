# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::BatchOperationGenerator do
  let(:context) { {} }
  let(:element) { { "config" => { "sourceVariable" => "items" } } }

  it_behaves_like "a code generator"

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"batch_operation.incompatible_scope",
          FlowchartRuntime::Batch::Error
        ) do
          ctx[:progress] = FlowchartRuntime::Batch.run(
            ctx,
            source: ctx[:items],
            operation: "find_each",
            batch_size: 1000
          ) do |record|
            FlowchartRuntime::Entries.save(ctx, record)
          end
        end
      end
    RUBY
  end

  it "generates the each_batch variant" do
    expect(generated_step(described_class.sample_input.merge("operationType" => "each_batch"))).to include("do |batch_rel|")
    expect(generated_step(described_class.sample_input.merge("operationType" => "each_batch"))).to include("batch_rel")
    expect(generated_step(described_class.sample_input.merge("operationType" => "each_batch"))).not_to include("update_all")
  end

  it "generates the update_all variant" do
    config = described_class.sample_input.merge(
      "operationType" => "update_all",
      "fieldAssignments" => [{ "key" => "email", "value" => '"x"' }]
    )
    expect(generated_step(config)).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"batch_operation.incompatible_scope",
          FlowchartRuntime::Batch::Error
        ) do
          ctx[:progress] = FlowchartRuntime::Batch.run(
            ctx,
            source: ctx[:items],
            operation: "update_all",
            batch_size: 1000,
            assignments: {"email" => "x"}
          )
        end
      end
    RUBY
  end

  it "generates the destroy_all variant" do
    expect(generated_step(described_class.sample_input.merge("operationType" => "destroy_all"))).to include('operation: "destroy_all"')
    expect(generated_step(described_class.sample_input.merge("operationType" => "destroy_all"))).not_to include("do |record|")
  end

  it "emits another entity and own record scope" do
    code = generated_step(described_class.sample_input.merge("entity" => "Booking", "recordScope" => "own"))
    expect(code).to include('entity: "Booking"', 'record_scope: "own"')
  end

  it "requires assignments for update_all" do
    expect(errors(described_class.sample_input.merge("operationType" => "update_all")).map(&:code)).to include(:assignments_required)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:entity) { create(:entity, customer: customer, property_schema: [{ "name_slug" => "email", "type" => "String" }].to_json) }
    let!(:own) { create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {}) }
    let!(:foreign) { create(:entity_entry, customer: other, entity: entity) }

    it "destroys only the bound tenant's rows and fails a limited source through Step.fail" do
      ctx = {
        items: EntityEntry.all,
        bound_entity: entity,
        customer_id: customer.id,
        errors: [],
        error_details: []
      }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "sourceVariable" => "items", "operationType" => "destroy_all", "batchSize" => 100 },
        ctx: ctx
      )
      expect(result[:outcome]).to eq(1)
      expect(EntityEntry.exists?(own.id)).to be(false)
      expect(EntityEntry.exists?(foreign.id)).to be(true)

      limited = ctx.merge(
        items: EntityEntry.where(customer_id: customer.id).limit(10),
        errors: [],
        error_details: []
      )
      create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {})
      limited_result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "sourceVariable" => "items", "operationType" => "destroy_all" },
        ctx: limited
      )
      expect(limited_result[:outcome]).to be(false)
      expect(limited[:errors]).to include(I18n.t("flowchart_runtime.errors.batch_operation.incompatible_scope"))
    end

    it "caps destroy_all at maxRecords for this tenant only" do
      extra = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: {})
      ctx = {
        items: EntityEntry.all,
        bound_entity: entity,
        customer_id: customer.id,
        errors: [],
        error_details: []
      }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "sourceVariable" => "items", "operationType" => "destroy_all", "maxRecords" => 1, "batchSize" => 100 },
        ctx: ctx
      )
      expect(result[:code]).to include("max_records: 1")
      expect(result[:outcome]).to eq(1)
      remaining = [own, extra].count { |row| EntityEntry.exists?(row.id) }
      expect(remaining).to eq(1)
      expect(EntityEntry.exists?(foreign.id)).to be(true)
    end
  end
end
