# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::ListMessages do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  def call
    described_class.call(customer: customer, user: user)
  end

  before { Current.customer = customer }

  it "returns 403 when the module is not enabled" do
    create(:ai_assistant_provider_settings)
    expect(call.http_status).to eq(403)
    expect(call.errors).to include(I18n.t("ai_assistant.errors.module_disabled"))
  end

  it "returns 403 when no generation assignee is configured" do
    enable_ai_assistant_module!(customer)
    expect(call.http_status).to eq(403)
    expect(call.errors).to include(I18n.t("ai_assistant.errors.unconfigured"))
  end

  it "returns 403 when only a transcribe assignee is configured" do
    enable_ai_assistant!(customer, transcribe_active: true, generation_active: false)
    expect(call.http_status).to eq(403)
    expect(call.errors).to include(I18n.t("ai_assistant.errors.unconfigured"))
  end

  context "when the module and a generation assignee are active" do
    before { enable_ai_assistant!(customer) }

    it "returns an empty list when the user has no conversation" do
      result = call
      expect(result.success?).to eq(true)
      expect(result.messages).to eq([])
      expect(result.pending_reply).to eq(false)
    end

    it "returns messages in id order without treating an unanswered user turn as pending" do
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      first = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Hi")
      create(:ai_assistant_message, :assistant, customer: customer, conversation: conversation, body: "Hello")
      last = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Next")

      result = call
      expect(result.messages.map(&:id)).to eq([ first.id, result.messages[1].id, last.id ])
      expect(result.pending_reply).to eq(false)
    end

    it "reports pending_reply during regenerate when the last row is still the assistant turn" do
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      user_turn = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Hi")
      create(:ai_assistant_message, :assistant, customer: customer, conversation: conversation, body: "Hello")
      AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: user_turn)

      result = call
      expect(result.messages.last.role).to eq("assistant")
      expect(result.pending_reply).to eq(true)
    end

    # The desktop client polls this endpoint, so an unbounded history meant
    # every poll serialized the whole conversation.
    it "returns at most MESSAGE_LIMIT messages, keeping the most recent" do
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      created = Array.new(described_class::MESSAGE_LIMIT + 10) do |i|
        create(:ai_assistant_message, customer: customer, conversation: conversation, body: "turn #{i}")
      end

      result = call
      expect(result.messages.length).to eq(described_class::MESSAGE_LIMIT)
      expect(result.messages.first.id).to eq(created[10].id)
      expect(result.messages.last.id).to eq(created.last.id)
      expect(result.pending_reply).to eq(false)
    end

    it "reports no pending reply for a terminal generation even if its pointer remains" do
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      turn = create(:ai_assistant_message, customer: customer, conversation: conversation)
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: turn)
      generation.update!(status: "failed", failure_code: "enqueue_failed", finished_at: Time.current)
      expect(call.pending_reply).to eq(false)
    end

    it "does not include another tenant's conversation for the same user id" do
      other_customer = create(:customer)
      other_convo = create(:ai_assistant_conversation, customer: other_customer)
      create(:ai_assistant_message, customer: other_customer, conversation: other_convo, body: "Secret")

      expect(call.messages).to eq([])
    end

    it "does not include another user's conversation in the same tenant" do
      other = create(:user, :admin, customer: customer)
      other_convo = create(:ai_assistant_conversation, customer: customer, user: other)
      create(:ai_assistant_message, customer: customer, conversation: other_convo, body: "Secret")

      expect(call.messages).to eq([])
    end
  end
end
