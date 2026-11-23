# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator, "calculated fields" do
  let_it_be(:customer) { create(:customer) }
  around { |example| Current.set(customer: customer, user: nil, shared_resources_mode: false) { example.run } }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Float", "html_type" => "number" }
    ].to_json)
  end

  let(:configuration) do
    {
      "pages" => [
        {
          "id" => "page_1",
          "name" => "Order",
          "fields" => [
            { "id" => "f1", "field_type" => "number", "label" => "Price", "property_slug" => "price",
              "property_type" => "number", "html_type" => "number", "width" => "full" },
            { "id" => "f2", "field_type" => "number", "label" => "Total", "property_slug" => "total",
              "property_type" => "number", "html_type" => "number", "width" => "full",
              "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
          ]
        }
      ],
      "fields" => [],
      "metadata" => { "entity_id" => entity.id },
      "rules" => [],
      "calculations" => []
    }
  end

  let(:page) { create(:page, customer: customer, entity: entity, configuration: configuration.to_json) }
  let(:content) { described_class.new(page).generate }

  it "renders both the price and computed total fields with the computed one disabled" do
    expect(content).to include("total")
    expect(content).to include("price")
    expect(content).to include("disabled: true")
  end

  it "marks only the single computed field as disabled" do
    occurrences = content.scan("disabled: true").length

    expect(occurrences).to eq(1)
  end

  it "renders both fields using NumberFieldComponent" do
    expect(content.scan("FormFields::NumberFieldComponent").length).to eq(2)
  end

  context "when no fields are computed" do
    let(:configuration) do
      {
        "pages" => [
          {
            "id" => "page_1",
            "name" => "Order",
            "fields" => [
              { "id" => "f1", "field_type" => "number", "label" => "Price", "property_slug" => "price",
                "property_type" => "number", "html_type" => "number", "width" => "full" }
            ]
          }
        ],
        "fields" => [],
        "metadata" => { "entity_id" => entity.id },
        "rules" => [],
        "calculations" => []
      }
    end

    it "does not include disabled attribute" do
      expect(content).not_to include("disabled: true")
    end
  end
end
