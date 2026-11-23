# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Palette do
  before { described_class.reset! }

  it "includes registered step actions from ActionCatalog" do
    actions = described_class.document.fetch("step_actions")
    new_model = actions.find { |row| row["action"] == "new_model" }
    assign_value = actions.find { |row| row["action"] == "assign_value" }

    expect(new_model).to include("category" => "model")
    expect(new_model["description"]).to be_present
    expect(assign_value).to include("category" => "data")
    expect(assign_value["config_fields"]).to be_an(Array)
    expect(actions.map { |row| row["action"] }).to match_array(CodeGenerators::ActionCatalog.export(locale: "en")["actions"].map { |row| row["key"] })
  end

  it "documents Query Models with the declared generator fields" do
    query_models = described_class.document.fetch("step_actions").find { |row| row["action"] == "query_models" }
    fields = query_models.fetch("config_fields")
    by_name = fields.index_by { |field| field["name"] }

    expect(query_models["category"]).to eq("model")
    expect(by_name).not_to have_key("queryType")
    expect(by_name.fetch("conditions")).to include("role" => "conditions")
    expect(by_name.fetch("orderBy")).to include("role" => "literal")
    expect(by_name.fetch("resultVar")).to include("default" => "models")
    expect(by_name.fetch("orderDirection")).to include("default" => "asc")
    expect(by_name.fetch("distinct")).to include("default" => false)
  end

  it "documents structural element types including process, decision, and loop" do
    types = described_class.document.fetch("element_types")
    expect(types.map { |row| row["type"] }).to include("start", "end", "process", "decision", "loop", "subflow")
    expect(types.map { |row| row["type"] }).not_to include("timer")
    decision = types.find { |row| row["type"] == "decision" }
    expect(decision.fetch("config_fields").map { |field| field["name"] }).to include("routeBy", "subject", "condition")
  end

  it "groups actions into ActionCatalog categories" do
    keys = described_class.document.fetch("categories").map { |row| row["key"] }
    expect(keys).to include("model")
    expect(keys).not_to include("model_operations")
  end

  it "resolves canonical keys and rejects deleted actions" do
    expect(described_class.canonical_key("query_models")).to eq("query_models")
    expect(described_class).to be_known_action("new_model")
    expect(described_class).not_to be_known_action("validate")
    expect(described_class.canonical_key("validate")).to be_nil
  end
end
