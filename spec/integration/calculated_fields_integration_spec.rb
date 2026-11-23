# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calculated fields integration", type: :model do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, name: "Invoice", customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
      { "name" => "Discount", "name_slug" => "discount", "type" => "Float", "html_type" => "number" },
      { "name" => "Subtotal", "name_slug" => "subtotal", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * quantity" },
      { "name" => "Tax", "name_slug" => "tax", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "subtotal * 0.1" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "subtotal + tax - discount" }
    ].to_json)
  end

  before do
    # Invoice 1: price=100, qty=2, discount=10 → subtotal=200, tax=20, total=210
    create(:entity_entry, entity: entity, customer: customer,
      data: { "price" => "100", "quantity" => "2", "discount" => "10" }.to_json)
    # Invoice 2: price=50, qty=4, discount=0 → subtotal=200, tax=20, total=220
    create(:entity_entry, entity: entity, customer: customer,
      data: { "price" => "50", "quantity" => "4", "discount" => "0" }.to_json)
    # Invoice 3: price=75, qty=1, discount=5 → subtotal=75, tax=7.5, total=77.5
    create(:entity_entry, entity: entity, customer: customer,
      data: { "price" => "75", "quantity" => "1", "discount" => "5" }.to_json)
  end

  def query_builder
    FlowchartRuntime::QueryBuilder.for_entity(entity, customer_id: customer.id)
  end

  it "auto-injects all chained calculated fields" do
    result = query_builder.execute

    expect(result.sql).to include("AS subtotal")
    expect(result.sql).to include("AS tax")
    expect(result.sql).to include("AS total")
  end

  it "computes correct values for chained fields" do
    result = query_builder
      .order("total", "desc")
      .execute

    totals = result.records.map { |r| r["total"] }
    expect(totals[0]).to eq(220.0)
    expect(totals[1]).to eq(210.0)
    expect(totals[2]).to eq(77.5)
  end

  it "filters by calculated field" do
    conditions = {
      "operator" => "AND",
      "rules" => [{ "field" => "data.total", "op" => ">", "value" => "215" }]
    }
    result = query_builder
      .where(conditions, {})
      .execute

    expect(result.records.size).to eq(1)
    expect(result.records.first["total"]).to eq(220.0)
  end

  it "orders by calculated field" do
    result = query_builder
      .order("subtotal", "asc")
      .execute

    subtotals = result.records.map { |r| r["subtotal"] }
    expect(subtotals).to eq([75.0, 200.0, 200.0])
  end

  it "composes calculated fields with pagination" do
    result = query_builder
      .order("total", "desc")
      .paginate(page: 1, per_page: 2)
      .execute

    expect(result.records.size).to eq(2)
    expect(result.total_count).to eq(3)
    expect(result.records.first["total"]).to eq(220.0)
  end

  it "entity helpers work correctly" do
    expect(entity.calculated_fields.size).to eq(3)
    expect(entity.input_fields.size).to eq(3)
  end

  it "entity entry validation allows data without calculated fields" do
    entry = EntityEntry.new(entity: entity, customer: customer,
      data: { "price" => "100", "quantity" => "2", "discount" => "10" }.to_json)
    expect(entry).to be_valid
  end
end
