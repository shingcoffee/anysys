# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::BulkImportGenerator do
  let(:context) { {} }
  let(:element) { { "config" => { "sourceVariable" => "records" } } }

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
        result = FlowchartRuntime::BulkImport.run(
          ctx,
          rows: ctx[:records],
          on_duplicate: "skip",
          unique_by: []
        )
        return false unless result
        ctx[:import_result] = result
        ctx[:import_errors] = result.is_a?(Hash) ? result[:errors] : []
        result
      end
    RUBY
  end

  %w[skip update].each do |mode|
    it "emits onDuplicateKey #{mode}" do
      config = described_class.sample_input.merge("onDuplicateKey" => mode, "uniqueBy" => %w[email])
      expect(errors(config)).to eq([])
      expect(generated_step(config)).to include("on_duplicate: #{mode.inspect}")
    end
  end

  it "emits another entity and own record scope" do
    config = described_class.sample_input.merge("entity" => "Booking", "recordScope" => "own", "uniqueBy" => %w[email])
    expect(generated_step(config)).to include('entity: "Booking"', 'record_scope: "own"')
  end

  it "requires uniqueBy when updating duplicates" do
    expect(errors(described_class.sample_input.merge("onDuplicateKey" => "update")).map(&:code)).to include(:required)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "email", "type" => "String" },
        { "name_slug" => "status", "type" => "String" }
      ].to_json)
    end

    it "imports into this tenant only and fails over MAX_ROWS with a translated message" do
      create(:entity_entry, :with_data, entity: entity, customer: other, entry_data: { "email" => "shared@x.io", "status" => "foreign" })
      ctx = {
        records: [{ "email" => "shared@x.io", "status" => "new" }],
        bound_entity: entity,
        customer_id: customer.id,
        errors: [],
        error_details: []
      }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "sourceVariable" => "records", "onDuplicateKey" => "skip", "uniqueBy" => %w[email], "resultVar" => "import_result" },
        ctx: ctx
      )
      expect(result[:outcome]).to include(created: 1, updated: 0, skipped: 0, failed: 0)
      created = EntityEntry.where(customer_id: customer.id, entity_id: entity.id)
      expect(created.count).to eq(1)
      expect(created.first.email).to eq("shared@x.io")
      expect(EntityEntry.where(customer_id: other.id).first.status).to eq("foreign")

      too_many = ctx.merge(
        records: Array.new(described_class::MAX_ROWS + 1) { |i| { "email" => "u#{i}@x.io" } },
        errors: [],
        error_details: []
      )
      failed = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "sourceVariable" => "records", "onDuplicateKey" => "skip", "resultVar" => "import_result" },
        ctx: too_many
      )
      expect(failed[:outcome]).to be(false)
      expect(too_many[:errors]).to include(
        I18n.t("flowchart_runtime.errors.bulk_import.too_many_rows", count: described_class::MAX_ROWS + 1, max: described_class::MAX_ROWS)
      )
    end

    it "maps source columns onto entity attributes and records skipped-row errors" do
      ctx = {
        records: [{ "addr" => "map@x.io", "state" => "new" }],
        bound_entity: entity,
        customer_id: customer.id,
        errors: [],
        error_details: []
      }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "sourceVariable" => "records",
          "onDuplicateKey" => "skip",
          "uniqueBy" => %w[email],
          "fieldMappings" => [{ "key" => "addr", "value" => "email" }, { "key" => "state", "value" => "status" }],
          "resultVar" => "import_result",
          "errorsVar" => "import_errors"
        },
        ctx: ctx
      )
      expect(result[:outcome]).to include(created: 1, failed: 0)
      created = EntityEntry.where(customer_id: customer.id, entity_id: entity.id)
      expect(created.first.email).to eq("map@x.io")
      expect(created.first.status).to eq("new")
      expect(ctx[:import_errors]).to eq([])
    end

    it "fails the step on the first row error when onRowError is fail" do
      boom = Object.new
      def boom.to_h
        raise StandardError, "row exploded"
      end
      ctx = {
        records: [{ "email" => "ok@x.io", "status" => "a" }, boom],
        bound_entity: entity,
        customer_id: customer.id,
        errors: [],
        error_details: []
      }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "sourceVariable" => "records",
          "onDuplicateKey" => "skip",
          "onRowError" => "fail",
          "resultVar" => "import_result"
        },
        ctx: ctx
      )
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(
        I18n.t("flowchart_runtime.errors.bulk_import.row_failed", index: 1, reason: "row exploded")
      )
    end
  end
end
