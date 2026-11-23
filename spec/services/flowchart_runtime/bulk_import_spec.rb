# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::BulkImport do
  it "saves new rows through Entries.save rather than record.save!" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Email", "name_slug" => "email", "data_type" => "string" }
    ].to_json)
    ctx = { bound_entity: entity, customer_id: customer.id, audience: "admin", errors: [], error_details: [] }
    allow(::Entries::Save).to receive(:call).and_call_original

    described_class.run(ctx, rows: [{ "email" => "a@x.io" }], on_duplicate: "skip", unique_by: %w[email])

    expect(::Entries::Save).to have_received(:call).with(hash_including(audience: "admin"))
    expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(1)
  end

  it "fails through Step.fail when the row list exceeds MAX_ROWS" do
    ctx = { errors: [], error_details: [] }
    rows = Array.new(described_class::MAX_ROWS + 1) { { "email" => "a@x.io" } }

    expect(described_class.run(ctx, rows: rows, on_duplicate: "skip", unique_by: [])).to be(false)
    expect(ctx[:errors]).to include(
      I18n.t("flowchart_runtime.errors.bulk_import.too_many_rows", count: rows.size, max: described_class::MAX_ROWS)
    )
  end

  it "fails on the first row error when on_row_error is fail" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [{ "name_slug" => "email", "type" => "String" }].to_json)
    ctx = { bound_entity: entity, customer_id: customer.id, errors: [], error_details: [] }
    boom = Object.new
    def boom.to_h
      raise StandardError, "row exploded"
    end

    expect(
      described_class.run(ctx, rows: [boom], on_duplicate: "skip", unique_by: [], on_row_error: "fail")
    ).to be(false)
    expect(ctx[:errors]).to include(
      I18n.t("flowchart_runtime.errors.bulk_import.row_failed", index: 0, reason: "row exploded")
    )
  end

  it "rolls back rows from earlier batches when a later row fails the import" do
    customer = create(:customer)
    entity = create(:entity, customer: customer,
                             property_schema: [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }].to_json)
    ctx = { bound_entity: entity, customer_id: customer.id, errors: [], error_details: [] }
    boom = Object.new
    def boom.to_h
      raise StandardError, "row exploded"
    end

    rows = [{ "email" => "a@x.io" }, { "email" => "b@x.io" }, boom]
    expect(described_class.run(ctx, rows: rows, on_duplicate: "skip", unique_by: [], batch_size: 1, on_row_error: "fail"))
      .to be(false)
    expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count).to eq(0)
  end
end
