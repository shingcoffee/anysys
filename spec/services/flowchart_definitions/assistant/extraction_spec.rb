# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Assistant::Extraction do
  it "parses an apply_flowchart document" do
    extraction = described_class.parse({
      intent: "apply_flowchart",
      reply: "Creating Create Student.",
      flowchart: { "name" => "Create Student", "entity_name" => "Student" }
    }.to_json)
    expect(extraction).to be_valid
    expect(extraction).to be_persistable
    expect(extraction.flowchart["name"]).to eq("Create Student")
  end

  it "allows an empty reply for chat" do
    extraction = described_class.parse({ intent: "chat", reply: "", flowchart: nil }.to_json)
    expect(extraction).to be_valid
    expect(extraction).not_to be_persistable
  end

  it "rejects an empty reply for apply_flowchart" do
    extraction = described_class.parse({ intent: "apply_flowchart", reply: "  ", flowchart: { "name" => "X" } }.to_json)
    expect(extraction).not_to be_valid
  end

  it "keeps sanitized questions and the steps that need setup" do
    extraction = described_class.parse({
      intent: "clarify",
      reply: "I need the address.",
      flowchart: nil,
      questions: [{ prompt: "Which URL should receive the webhook?", type: "text" }, { prompt: "" }],
      needs_setup: ["Webhook signing secret", "", 42, "  Webhook signing secret "]
    }.to_json)

    expect(extraction).to be_valid
    expect(extraction.questions).to eq([
      { "id" => "q1", "prompt" => "Which URL should receive the webhook?", "type" => "text",
        "options" => [], "default" => nil }
    ])
    expect(extraction.needs_setup).to eq(["Webhook signing secret"])
  end

  it "defaults questions and needs_setup to empty lists" do
    extraction = described_class.parse({ intent: "chat", reply: "", flowchart: nil }.to_json)

    expect(extraction.questions).to eq([])
    expect(extraction.needs_setup).to eq([])
  end

  it "rejects an unknown intent" do
    extraction = described_class.parse({ intent: "apply_entities", reply: "nope", flowchart: nil }.to_json)
    expect(extraction).not_to be_valid
  end
end
