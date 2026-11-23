# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::StructureSchema do
  before { FlowchartDefinitions::Palette.reset! }

  it "loads a JSON object with flowchart structured-output keys" do
    schema = described_class.json
    expect(schema["required"]).to include("intent", "reply")
    expect(schema.dig("properties", "intent", "enum")).to contain_exactly("chat", "clarify", "apply_flowchart")
  end

  it "embeds the ActionCatalog palette and CRUD rules in the prompt" do
    prompt = described_class.prompt
    expect(prompt).to include("apply_flowchart")
    expect(prompt).to include("new_model")
    expect(prompt).to include("assign_value")
    expect(prompt).to include("validate_contract")
    expect(prompt).to include("decision")
    expect(prompt).to include("updates_confirmed")
    expect(prompt).to include("create")
    expect(prompt).to include("ctx[:contract]")
    expect(prompt).to include("query_models")
    expect(prompt).to include("MUST include a config object")
    expect(prompt).to include(described_class.json["title"])
    expect(FlowchartDefinitions::Assistant::SchemaGenerator.prompt_palette.bytesize)
      .to be <= FlowchartDefinitions::Assistant::SchemaGenerator::PROMPT_PALETTE_BUDGET
  end

  it "limits process steps to one action" do
    steps = described_class.json.dig("$defs", "element", "properties", "steps")
    expect(steps["maxItems"]).to eq(1)
    expect(steps["description"]).to include("maxItems: 1")
  end

  it "does not offer the removed Timer element type" do
    types = described_class.json.dig("$defs", "element", "properties", "type", "enum")
    expect(types).to contain_exactly("start", "end", "process", "decision", "loop", "subflow")
    expect(described_class.prompt).not_to match(/\btimer\b/i)
  end

  it "enumerates canonical ActionCatalog keys on step.action" do
    enum = described_class.json.dig("$defs", "step", "properties", "action", "enum")
    expect(enum).to match_array(FlowchartDefinitions::Palette.canonical_keys)
    expect(enum).to include("validate_contract", "query_models", "save_model")
    expect(enum).not_to include("validate", "API_call")
  end

  it "keeps prompt examples free of deleted action and field names" do
    examples = described_class.prompt_examples.to_json
    expect(examples).not_to include('"validate"')
    expect(examples).not_to include("contractRef")
    expect(examples).not_to include("queryType")
    expect(examples).not_to include("sourceKey")
    expect(examples).not_to include("outputKey")
    expect(examples).not_to include("targetVariable")
    expect(examples).not_to include("API_call")
  end

  it "validates every example step against the target generator" do
    examples = described_class.prompt_examples
    expect(examples.size).to be >= 4

    examples.each do |document|
      next unless document["flowchart"].is_a?(Hash)

      Array(document.dig("flowchart", "elements")).each do |element|
        Array(element["steps"]).each do |step|
          action = step["action"].to_s
          config = step["config"].is_a?(Hash) ? step["config"] : {}
          klass = CodeGenerators::GeneratorRegistry.find_step_action(action)
          expect(klass).to be_present, "unregistered example action #{action}"
          errors = klass.new({ "config" => config }, {}).validate_config(config)
          expect(errors).to eq([]), "#{action}: #{errors.inspect}"
        end
      end
    end
  end
end
