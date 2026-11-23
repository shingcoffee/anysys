# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::WelcomePrompts do
  let(:customer) { create(:customer) }

  it "returns continue_prompt from the last user turn on the same thread" do
    conversation = create(:ai_assistant_conversation, customer: customer)
    create(:ai_assistant_message, conversation: conversation, customer: customer, body: "first")
    create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer, body: "ok")
    create(:ai_assistant_message, conversation: conversation, customer: customer, body: "latest")
    prompts = described_class.call(customer_id: customer.id, messages: conversation.messages.order(:id))
    expect(prompts.continue_prompt).to eq("latest")
  end

  it "lists recent customer-owned entities and pages, not another tenant" do
    entity = create(:entity, customer: customer, name: "Student")
    page = create(:page, customer: customer, name: "Homepage")
    other = create(:customer)
    create(:entity, customer: other, name: "Foreign")
    prompts = described_class.call(customer_id: customer.id, messages: [])
    labels = prompts.chips.map(&:label)
    expect(labels).to include("Student", "Homepage")
    expect(labels).not_to include("Foreign")
    expect(prompts.chips.find { |chip| chip.label == "Student" }.prompt).to eq(
      I18n.t("ai_assistant.assistant.prompts.recent_entity", name: entity.name)
    )
    expect(prompts.chips.find { |chip| chip.label == "Homepage" }.prompt).to eq(
      I18n.t("ai_assistant.assistant.prompts.recent_page", name: page.name)
    )
  end
end
