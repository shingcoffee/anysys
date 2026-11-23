# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::CancelReply do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation)
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
  end

  around { |example| Current.set(customer: customer) { example.run } }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
  end

  it "cancels the current generation" do
    generation
    result = described_class.call(customer: customer, user: user)
    expect(result.success?).to eq(true)
    expect(generation.reload.status).to eq("cancelled")
    expect(generation.cancelled_at).to be_present
  end

  it "does not cancel another user's conversation" do
    generation
    other = create(:user, :admin, customer: customer)
    described_class.call(customer: customer, user: other)
    expect(generation.reload.status).to eq("queued")
  end

  it "is a no-op when no generation is running" do
    conversation
    result = described_class.call(customer: customer, user: user)
    expect(result.success?).to eq(true)
    expect(conversation.reload.current_generation).to be_nil
  end

  # A panel whose running flag has drifted out of step with the server is the
  # only reason to press Stop with nothing live, so that request is the one
  # chance to put it back into a usable state.
  it "publishes idle when there was nothing to cancel" do
    conversation
    described_class.call(customer: customer, user: user)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(anything, hash_including(target: AiAssistant::Stream::RUNNING_ID, html: /data-running="false"/))
    expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
      .with(anything, hash_including(target: AiAssistant::Stream::STATUS_ID, html: ""))
  end

  it "succeeds without opening a thread when the user has never chatted" do
    expect {
      expect(described_class.call(customer: customer, user: user)).to be_success
    }.not_to change(AiAssistant::Conversation, :count)
  end

  it "cancels the named thread rather than the most recent one" do
    generation
    create(:ai_assistant_conversation, customer: customer, user: user)

    described_class.call(customer: customer, user: user, conversation_id: conversation.id)

    expect(generation.reload.status).to eq("cancelled")
  end

  it "returns 404 for another user's thread" do
    generation
    other = create(:user, :admin, customer: customer)

    result = described_class.call(
      customer: customer, user: other, conversation_id: conversation.id
    )

    expect(result.http_status).to eq(404)
    expect(generation.reload.status).to eq("queued")
  end

  it "returns 404 for the same user's thread in another tenant" do
    generation

    result = described_class.call(
      customer: create(:customer), user: user, conversation_id: conversation.id
    )

    expect(result.http_status).to eq(404)
    expect(generation.reload.status).to eq("queued")
  end
end
