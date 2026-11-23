# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Tools::OperationTool do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let(:session) do
    AiAssistant::Assistant::Tools::Session.new(
      customer: customer,
      viewer: admin,
      conversation: conversation
    )
  end
  let(:tool) { described_class.new(session: session, operation: Operations::GetEntity) }

  it "exposes the operation key, summary, and projected schema" do
    definition = Operations::GetEntity.tool_definition(session.operation_context)

    expect(tool.name).to eq("get_entity")
    expect(tool.description).to eq(Operations::GetEntity.summary)
    expect(tool.params_schema).to eq(definition[:parameters])
    expect(tool.params_schema).to include("type" => "object")
  end

  it "returns the session result as JSON" do
    create(:entity, customer: customer, name: "Student")

    payload = JSON.parse(tool.execute(entity: "Student"))

    expect(payload).to include("ok" => true, "status" => "succeeded", "operation" => "get_entity")
    expect(payload.dig("data", "entity", "name")).to eq("Student")
    expect(payload.dig("data", "entity")).to include("attributes", "attribute_groups")
  end
end
