# frozen_string_literal: true

require "rails_helper"

RSpec.describe "QueryBuilder integration", type: :model do
  let(:customer) { create(:customer) }
  let(:product_entity) do
    create(:entity, name: "Product", customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Category", "name_slug" => "category", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:order_entity) do
    create(:entity, name: "Order", customer: customer, property_schema: [
      { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end
  let(:bridge_entity) do
    create(:entity, name: "assoc_product_order", customer: customer, category: :bridge, property_schema: [
      { "name" => "Product", "name_slug" => "product", "type" => "EntityReference", "entity_id" => product_entity.id.to_s },
      { "name" => "Order", "name_slug" => "order", "type" => "EntityReference", "entity_id" => order_entity.id.to_s }
    ].to_json)
  end

  def builder_for(entity = product_entity)
    FlowchartRuntime::QueryBuilder.for_entity(entity, customer_id: customer.id)
  end

  before do
    @p1 = create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Widget", "price" => "10", "category" => "tools" }.to_json)
    @p2 = create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Gadget", "price" => "20", "category" => "tools" }.to_json)
    @p3 = create(:entity_entry, entity: product_entity, customer: customer, data: { "title" => "Doohickey", "price" => "30", "category" => "misc" }.to_json)

    order1 = create(:entity_entry, entity: order_entity, customer: customer, data: { "total" => "100" }.to_json)

    create(:entity_entry, entity: bridge_entity, customer: customer,
      data: { "product" => @p1.id.to_s, "order" => order1.id.to_s }.to_json)
    create(:entity_entry, entity: bridge_entity, customer: customer,
      data: { "product" => @p2.id.to_s, "order" => order1.id.to_s }.to_json)
  end

  it "composes JOIN + WHERE + pagination + order" do
    result = builder_for
      .join_entity(order_entity, via: bridge_entity)
      .where({ "operator" => "AND", "rules" => [{ "field" => "data.category", "op" => "==", "value" => "tools" }] }, {})
      .order("data.title", "asc")
      .paginate(page: 1, per_page: 10)
      .execute

    names = result.records.map { |r| r.data_json["title"] }
    expect(names).to eq(%w[Gadget Widget])
    expect(result.total_count).to eq(2)
    expect(result.has_next).to be false
  end

  it "rejects manual computed SQL expressions" do
    expect {
      builder_for
        .computed_field("price_doubled", "CAST(json_extract(data, '$.price') AS NUMERIC) * 2")
        .order("price_doubled", "desc")
        .execute
    }.to raise_error(FlowchartRuntime::QueryBuilder::Error, /manual computed SQL expressions are not supported/)
  end

  it "composes GROUP BY + aggregate" do
    result = builder_for
      .group("data.category")
      .aggregate(:count)
      .execute

    expect(result.records).to be_a(Hash)
    expect(result.records["tools"]).to eq(2)
    expect(result.records["misc"]).to eq(1)
  end

  it "uses sub-query in WHERE" do
    conditions = {
      "operator" => "AND",
      "rules" => [{
        "field" => "data.price",
        "op" => ">",
        "subQuery" => {
          "entityId" => product_entity.id,
          "aggregateFunction" => "avg",
          "aggregateField" => "price"
        }
      }]
    }

    result = builder_for
      .where(conditions, {})
      .execute

    # AVG price = 20, so only price=30 matches
    expect(result.records.size).to eq(1)
    expect(result.records.first.data_json["title"]).to eq("Doohickey")
  end

  it "returns sql in result for debugging" do
    result = builder_for.execute

    expect(result.sql).to be_a(String)
    expect(result.sql).to include("entity_entries")
  end
end
