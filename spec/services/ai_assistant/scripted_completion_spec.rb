# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ScriptedCompletion do
  def document(messages)
    JSON.parse(described_class.call(messages: messages)[:text])
  end

  it "is enabled only in development with E2E_STUB_ASSISTANT=1" do
    with_e2e_assistant_stub do
      expect(described_class).to be_enabled
    end
  end

  it "emits a create_entity tool call for a Create-a-Name request" do
    payload = document([ { role: "user", content: "Create a FooBar entity" } ])
    expect(payload["tool"]).to eq("create_entity")
    expect(payload.dig("arguments", "domain")).to eq("Academics")
    expect(payload.dig("arguments", "entities").first["name"]).to eq("FooBar")
    expect(payload.dig("arguments", "entities").first["attributes"]).to include(
      hash_including("name" => "Title")
    )
  end

  it "emits an update_entity tool call when the user asks to add a field" do
    payload = document([
      { role: "user", content: "Create a FooBar entity" },
      { role: "user", content: "Add a notes field to FooBar" }
    ])
    expect(payload["tool"]).to eq("update_entity")
    expect(payload.dig("arguments", "updates").first).to include("entity" => "FooBar")
    expect(payload.dig("arguments", "updates").first["changes"]).to include(
      hash_including("op" => "add_attribute", "attribute" => hash_including("name" => "Notes"))
    )
  end

  it "emits the final envelope after a tool result" do
    payload = document([
      { role: "user", content: "Create a FooBar entity" },
      { role: "user", content: { "tool_result" => { "status" => "succeeded", "data" => { "created" => [{ "name" => "FooBar" }] } } }.to_json }
    ])
    expect(payload["intent"]).to eq("chat")
    expect(payload["reply"]).to include("FooBar")
  end

  it "returns a chat no-op for a flowchart system prompt" do
    payload = document([
      { role: "system", content: "intent apply_flowchart" },
      { role: "user", content: "Create a FooBar entity" }
    ])
    expect(payload["intent"]).to eq("chat")
    expect(payload["flowchart"]).to be_nil
  end
end
