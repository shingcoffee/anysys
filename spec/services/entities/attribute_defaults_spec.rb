# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::AttributeDefaults do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, default_properties: { "name" => "Anon", "status" => "Closed" }.to_json,
                    property_schema: [
                      { "name_slug" => "name" },
                      { "name_slug" => "status", "html_type" => "select",
                        "config" => { "options" => [{ "value" => "Open", "default" => true }, { "value" => "Closed" }] } },
                      { "name_slug" => "stage", "html_type" => "radio",
                        "config" => { "options" => [{ "value" => "New", "default" => true }, { "value" => "Done" }] } },
                      { "name_slug" => "tags", "html_type" => "multi-select",
                        "config" => { "options" => [{ "value" => "a", "default" => true }, { "value" => "b", "default" => true }] } },
                      { "name_slug" => "size", "html_type" => "select",
                        "config" => { "options" => [{ "value" => "S", "default" => true }, { "value" => "L", "default" => true }] } },
                      { "name_slug" => "note", "html_type" => "select", "config" => { "options" => ["x", "y"] } }
                    ].to_json)
  end

  it "takes the stored default first, else the options flagged default" do
    expect(described_class.call(entity, %w[name status stage tags size note missing]))
      .to eq("name" => "Anon", "status" => "Closed", "stage" => "New", "tags" => %w[a b])
  end

  it "answers only for the slugs asked" do
    expect(described_class.call(entity, %w[stage])).to eq("stage" => "New")
  end

  it "lists the values an attribute's options flag default" do
    attribute = entity.property_schema_json.find { |row| row["name_slug"] == "tags" }

    expect(described_class.flagged(attribute)).to eq(%w[a b])
  end
end
