# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::SchemaProjection do
  let_it_be(:customer) { create(:customer) }
  let(:context) { Operations::Context.new(customer: customer, channel: "assistant") }
  let(:document) { Operations::FakeEcho.input_schema(context).document }

  it "inlines local $refs and drops $schema, $id, $defs, examples, and x-* keys" do
    projected = described_class.call(document)

    expect(projected).not_to have_key("$schema")
    expect(projected).not_to have_key("$id")
    expect(projected).not_to have_key("$defs")
    expect(projected).not_to have_key("examples")
    expect(JSON.generate(projected)).not_to include("x-")
    expect(projected.dig("properties", "name", "type")).to eq("string")
    expect(projected.dig("properties", "name")).not_to have_key("$ref")
  end

  it "folds enum descriptions into the property description" do
    projected = described_class.call(document)
    description = projected.dig("properties", "color", "description")

    expect(description).to include("Accent color.")
    expect(description).to include("Allowed values:")
    expect(description).to include("`red` — A red accent")
    expect(description).not_to include(".;")
    expect(description).to end_with(".")
    expect(projected.dig("properties", "color")).not_to have_key("x-enum-descriptions")
  end

  it "folds conditionals into the parent description and rewrites oneOf to anyOf" do
    source = {
      "description" => "Root.",
      "oneOf" => [{ "type" => "string", "description" => "A string." }],
      "allOf" => [
        {
          "description" => "When flagged, value is required.",
          "if" => { "properties" => { "flag" => { "const" => true } } },
          "then" => { "required" => ["value"] }
        }
      ]
    }
    projected = described_class.call(source)

    expect(projected).to have_key("anyOf")
    expect(projected).not_to have_key("oneOf")
    expect(projected).not_to have_key("allOf")
    expect(projected).not_to have_key("if")
    expect(projected["description"]).to include("When flagged, value is required.")
  end

  it "raises TooLarge when the projection exceeds the budget" do
    huge = { "description" => "x" * 100, "type" => "object", "properties" => {} }
    expect { described_class.call(huge, budget: 20) }.to raise_error(described_class::TooLarge)
  end
end
