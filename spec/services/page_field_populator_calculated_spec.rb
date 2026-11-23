# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageFieldPopulator, "calculated fields" do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
    ].to_json)
  end

  it "leaves calculated fields out of generated forms" do
    fields = described_class.call(entity).flat_map { |p| p["fields"] }

    expect(fields.map { |f| f["property_slug"] }).to eq(["price"])
  end

  it "keeps regular fields editable" do
    price_field = described_class.call(entity).flat_map { |p| p["fields"] }.find { |f| f["property_slug"] == "price" }

    expect(price_field["readonly"]).to be_falsey
  end
end
