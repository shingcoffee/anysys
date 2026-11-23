# frozen_string_literal: true

require "rails_helper"
require "json_schemer"

RSpec.describe "CodeGenerators::ActionCatalog contract" do
  let(:schema_path) { Rails.root.join("app/services/code_generators/action_catalog.schema.json") }
  let(:fixture_path) { Rails.root.join("spec/javascript/fixtures/action_catalog.sample.json") }
  let(:schemer) { JSONSchemer.schema(JSON.parse(File.read(schema_path))) }

  def validate(payload)
    schemer.validate(payload).map { |error| JSONSchemer::Errors.pretty(error) }
  end

  it "has a JSON Schema on disk" do
    expect(schema_path).to exist
  end

  it "validates the live English export" do
    expect(validate(CodeGenerators::ActionCatalog.export(locale: "en"))).to eq([])
  end

  it "validates the live Simplified Chinese export" do
    expect(validate(CodeGenerators::ActionCatalog.export(locale: "zh-CN"))).to eq([])
  end

  it "validates the committed JavaScript fixture" do
    expect(fixture_path).to exist
    fixture = JSON.parse(File.read(fixture_path))
    expect(validate(fixture)).to eq([])
    keys = fixture.fetch("actions").map { |action| action.fetch("key") }
    expect(keys).to include("phase3_fixture")
    controls = fixture.fetch("actions").flat_map { |action| action.fetch("fields").map { |field| field.fetch("control") } }
    expect(controls.uniq).to include(
      "text", "code", "textarea", "select", "toggle", "number", "list", "mapping",
      "conditions", "attribute_picker", "reference_picker", "localized_text"
    )
  end
end
