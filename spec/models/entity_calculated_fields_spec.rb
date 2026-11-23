# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entity, "calculated fields" do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Quantity", "name_slug" => "quantity", "type" => "Integer", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * quantity" }
    ].to_json)
  end

  describe "#calculated_fields" do
    it "returns only Calculated type fields" do
      result = entity.calculated_fields
      expect(result.size).to eq(1)
      expect(result.first["name_slug"]).to eq("total")
    end

    it "returns empty for entity with no calculated fields" do
      plain = create(:entity, customer: customer, property_schema: [
        { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" }
      ].to_json)
      expect(plain.calculated_fields).to eq([])
    end
  end

  describe "#input_fields" do
    it "returns only non-Calculated fields" do
      result = entity.input_fields
      expect(result.size).to eq(2)
      slugs = result.map { |f| f["name_slug"] }
      expect(slugs).to contain_exactly("price", "quantity")
    end
  end
end
