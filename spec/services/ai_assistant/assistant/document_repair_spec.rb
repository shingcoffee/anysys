# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::DocumentRepair do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  let(:document) { { "flowchart" => { "name" => "Create Student" } } }
  let(:errors) { [ "elements is missing", "" ] }

  def repair(chat, mode: :flowchart, instructions: "flowchart_repair", parser: FlowchartDefinitions::Assistant::Extraction)
    described_class.new(
      conversation: conversation,
      chat: chat,
      mode: mode,
      instructions: instructions,
      parser: parser
    ).call(document: document, errors: errors)
  end

  def reply(flowchart)
    {
      outcome: :success,
      text: { "reply" => "Fixed.", "intent" => "apply_flowchart", "flowchart" => flowchart, "updates_confirmed" => false }.to_json
    }
  end

  it "replays the thread, shows the model its rejected document, and returns the replacement" do
    sent = nil
    chat = ->(messages) do
      sent = messages
      reply({
        "name" => "Create Student",
        "entity_name" => "Student",
        "crud_type" => "create",
        "elements" => [
          { "id" => "start_1", "type" => "start", "label" => "Start" },
          { "id" => "end_1", "type" => "end", "label" => "End" }
        ],
        "connections" => [{ "from" => "start_1", "to" => "end_1" }]
      })
    end

    repaired = repair(chat)

    expect(repaired.flowchart["name"]).to eq("Create Student")
    expect(sent.first[:role]).to eq("system")
    expect(sent[-2]).to eq(role: "assistant", content: document.to_json)
    expect(sent.last[:role]).to eq("user")
    expect(sent.last[:content]).to include(
      AiAssistant::Assistant::Prompt::Document.read("flowchart_repair")
    )
    expect(sent.last[:content]).to include("elements is missing")
  end

  it "asks in the mode it was given so the two contracts cannot cross" do
    sent = nil
    chat = ->(messages) do
      sent = messages
      { outcome: :success, text: { "reply" => "Fixed.", "intent" => "apply_flowchart", "flowchart" => nil }.to_json }
    end

    repair(chat)

    expect(sent.first[:content]).to include(FlowchartDefinitions::StructureSchema.prompt)
    expect(sent.last[:content]).to include(
      AiAssistant::Assistant::Prompt::Document.read("flowchart_repair")
    )
  end

  describe "an unusable reply is not a repair" do
    it "returns nil when the vendor fails" do
      expect(repair(->(_messages) { { outcome: :error, text: "" } })).to be_nil
    end

    it "returns nil when the vendor returns something other than a result hash" do
      expect(repair(->(_messages) { nil })).to be_nil
    end

    it "returns nil on a blank reply" do
      expect(repair(->(_messages) { { outcome: :success, text: "   " } })).to be_nil
    end

    it "returns nil when the reply is not a valid document" do
      expect(repair(->(_messages) { { outcome: :success, text: "not json" } })).to be_nil
    end

    it "returns nil when the replacement no longer persists anything" do
      chat = ->(_messages) do
        { outcome: :success, text: { "reply" => "Which fields?", "intent" => "chat", "flowchart" => nil }.to_json }
      end

      expect(repair(chat)).to be_nil
    end
  end
end
