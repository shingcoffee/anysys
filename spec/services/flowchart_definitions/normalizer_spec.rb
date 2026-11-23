# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Normalizer do
  def fill(steps:)
    {
      "name" => "List Students",
      "entity_name" => "Student",
      "crud_type" => "read",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        { "id" => "p1", "type" => "process", "label" => "Query", "steps" => steps },
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => [
        { "from" => "start_1", "to" => "p1" },
        { "from" => "p1", "to" => "end_1" }
      ]
    }
  end

  it "keeps Query Models editor config on the process step" do
    result = described_class.call(fill(steps: [
      {
        "action" => "query_models",
        "config" => {
          "conditions" => { "status" => "active" },
          "orderBy" => "email",
          "orderDirection" => "asc",
          "resultVar" => "models"
        }
      }
    ]))

    expect(result).to be_ok
    step = result.configuration.dig("elements", 1, "properties", "steps", 0)
    expect(step["action"]).to eq("query_models")
    expect(step["config"]).to include(
      "conditions" => { "status" => "active" },
      "orderBy" => "email",
      "orderDirection" => "asc",
      "resultVar" => "models"
    )
    expect(step["config"]).not_to have_key("queryType")
  end

  it "fills schema defaults when the LLM omits Query Models config keys" do
    result = described_class.call(fill(steps: [{ "action" => "query_models" }]))
    expect(result).to be_ok
    config = result.configuration.dig("elements", 1, "properties", "steps", 0, "config")
    expect(config).to include(
      "resultVar" => "models",
      "orderDirection" => "asc",
      "distinct" => false,
      "returns" => "records"
    )
    expect(config).not_to have_key("queryType")
  end

  it "seeds End from the ported schema without hidden HTTP fields" do
    result = described_class.call(
      "name" => "Finish",
      "entity_name" => "Student",
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "end_1", "type" => "end" }
      ],
      "connections" => [{ "from" => "start_1", "to" => "end_1" }]
    )

    expect(result).to be_ok
    end_el = result.configuration.fetch("elements").find { |el| el["type"] == "end" }
    expect(end_el.dig("properties", "responseType")).to eq("none")
    expect(end_el["properties"]).not_to have_key("httpStatus")
    expect(end_el["properties"]).not_to have_key("returnValue")
  end

  it "labels omitted elements with the translated defaultLabel" do
    definition = {
      "name" => "Finish",
      "entity_name" => "Student",
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "end_1", "type" => "end" }
      ],
      "connections" => [{ "from" => "start_1", "to" => "end_1" }]
    }

    english = described_class.call(definition)
    expect(english.configuration.fetch("elements").map { |el| el["label"] }).to eq(%w[Start End])

    chinese = I18n.with_locale(:"zh-CN") { described_class.call(definition) }
    expect(chinese.configuration.fetch("elements").map { |el| el["label"] }).to eq(%w[开始 结束])
  end

  it "fills loop type defaults from the live Ruby schema when declared" do
    result = described_class.call(
      "name" => "Iterate",
      "entity_name" => "Student",
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "l1", "type" => "loop" },
        { "id" => "end_1", "type" => "end" }
      ],
      "connections" => [
        { "from" => "start_1", "to" => "l1" },
        { "from" => "l1", "to" => "end_1" }
      ]
    )

    expect(result).to be_ok
    loop_el = result.configuration.fetch("elements").find { |el| el["type"] == "loop" }
    expect(loop_el["properties"]).to include("loopType")
  end

  it "assigns deterministic connection ids when the LLM omits them" do
    result = described_class.call(fill(steps: [{ "action" => "query_models" }]))
    ids = result.configuration.fetch("connections").map { |connection| connection["id"] }
    expect(ids).to eq(%w[c_1 c_2])
  end

  it "splits a multi-action process before returning the configuration" do
    result = described_class.call(fill(steps: [
      { "action" => "new_model", "config" => { "resultVar" => "model" } },
      { "action" => "save_model", "config" => {} }
    ]))

    expect(result).to be_ok
    processes = result.configuration.fetch("elements").select { |el| el["type"] == "process" }
    expect(processes.size).to eq(2)
    expect(processes.map { |el| el.dig("properties", "steps").size }).to all(eq(1))
    expect(processes.map { |el| el.dig("properties", "steps", 0, "action") }).to eq(%w[new_model save_model])
  end
end
