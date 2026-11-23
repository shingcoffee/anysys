# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Loop do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }

  it "passes a non-tool document through unchanged" do
    text = { intent: "chat", reply: "Hi", entities: [] }.to_json
    result = described_class.call(text: text, conversation: conversation, customer: customer, chat: ->(_) { raise "no chat" })
    expect(result).to have_attributes(text: text, outcome: :success)
  end

  it "executes a tool then continues with the next model document" do
    chat = lambda do |_messages|
      { outcome: :success, text: { intent: "chat", reply: "Listed.", entities: [] }.to_json }
    end
    text = { "tool" => "list_catalog", "arguments" => {} }.to_json
    result = described_class.call(text: text, conversation: conversation, customer: customer, chat: chat)
    expect(result.outcome).to eq(:success)
    parsed = JSON.parse(result.text)
    expect(parsed["intent"]).to eq("chat")
    expect(parsed["reply"]).to eq("Listed.")
  end

  it "returns an explicit provider-failure outcome during a tool round trip" do
    text = { "tool" => "list_catalog", "arguments" => {} }.to_json

    result = described_class.call(
      text: text,
      conversation: conversation,
      customer: customer,
      chat: ->(_messages) { { outcome: :unreachable, text: nil, raw: {} } }
    )

    expect(result).to have_attributes(outcome: :provider_failure, text: nil)
  end

  it "returns an explicit max-steps outcome while the model keeps requesting tools" do
    text = { "tool" => "list_catalog", "arguments" => {} }.to_json
    calls = 0

    result = described_class.call(
      text: text,
      conversation: conversation,
      customer: customer,
      chat: lambda do |_messages|
        calls += 1
        { outcome: :success, text: text, raw: {} }
      end
    )

    expect(calls).to eq(described_class::MAX_STEPS)
    expect(result).to have_attributes(outcome: :max_steps, text: nil)
  end
end

RSpec.describe AiAssistant::Assistant::Tools::Session do
  let(:customer) { create(:customer) }
  let(:runner) { described_class.new(customer: customer) }

  it "returns this tenant's catalog only" do
    create(:entity, customer: customer, name: "Mine")
    other = create(:customer)
    create(:entity, customer: other, name: "Theirs")
    result = runner.call("list_catalog", {})
    names = Array(result["entities"]).map { |row| row["name"] || row[:name] }
    expect(names).to include("Mine")
    expect(names).not_to include("Theirs")
  end

  it "rejects an unknown tool" do
    result = runner.call("bash", {})
    expect(result["ok"]).to eq(false)
    expect(result["error"]).to include("bash")
  end

  it "builds native ruby_llm tool instances for this tenant" do
    tools = runner.native_tools
    expect(tools.map(&:name)).to include(
      "list_catalog", "generate_page", "verify_artifact",
      "create_domain", "create_entity", "update_entity", "get_entity"
    )
    expect(tools.first.execute["ok"]).to eq(true)
  end
end
