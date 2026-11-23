# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Assistant::SchemaGenerator do
  before { FlowchartDefinitions::Palette.reset! }

  it "projects every ActionCatalog action into the assistant palette" do
    catalog = CodeGenerators::ActionCatalog.export(locale: "en")
    document = described_class.palette_document

    expect(document.fetch("step_actions").map { |row| row["action"] })
      .to match_array(catalog.fetch("actions").map { |row| row["key"] })
    expect(document.fetch("categories").map { |row| row["key"] })
      .to eq(catalog.fetch("categories").map { |row| row["key"] })
  end

  it "fails when the committed palette snapshot differs from a fresh generation" do
    expected = described_class.palette_json
    actual = described_class::PALETTE_PATH.read
    expect(actual).to eq(expected),
                      "run `bin/rails ai_assistant:flowchart_schema` to regenerate #{described_class::PALETTE_PATH}"
  end

  it "keeps the compact prompt palette within the operations schema budget" do
    palette = described_class.prompt_palette
    expect(palette).to include("query_models", "validate_contract", "save_model")
    expect(palette.bytesize).to be <= described_class::PROMPT_PALETTE_BUDGET
  end
end
