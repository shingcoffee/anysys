# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AiAssistant::Assistant::GenerationHandoff" do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
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

  before do
    allow(AiAssistant::Stream).to receive(:broadcast_message)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    AiAssistant::Stream.broadcast_running(conversation, true)
    AiAssistant::Stream.broadcast_status(
      conversation,
      I18n.t("ai_assistant.assistant.status.thinking")
    )
  end

  def handoff
    AiAssistant::Assistant::GenerationHandoff.call(generation: generation)
  end

  def expect_failed_handoff
    result = handoff

    expect(result).to have_attributes(success?: false, failure_code: "enqueue_failed")
    expect(generation.reload).to have_attributes(
      status: "failed",
      failure_code: "enqueue_failed"
    )
    expect(generation.finished_at).to be_present
    expect(conversation.reload.current_generation).to be_nil
    expect(conversation.messages.where(role: "assistant").sole.metadata_json).to include(
      "generation_id" => generation.id, "failure_code" => "enqueue_failed"
    )
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(
        anything,
        hash_including(
          target: AiAssistant::Stream::RUNNING_ID,
          html: include('data-running="false"')
        )
      )
    expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
      .with(
        anything,
        hash_including(
          target: AiAssistant::Stream::STATUS_ID,
          html: ""
        )
      )
  end

  it "fails and closes the generation when Active Job refuses the enqueue" do
    allow(AiAssistant::ReplyJob).to receive(:perform_later)
      .with(generation.id)
      .and_return(false)

    expect_failed_handoff
  end

  it "fails and closes the generation when enqueue raises" do
    allow(AiAssistant::ReplyJob).to receive(:perform_later)
      .with(generation.id)
      .and_raise(ActiveJob::EnqueueError, "queue unavailable")

    expect_failed_handoff
  end

  it "keeps the terminal failure durable if message broadcasting raises" do
    allow(AiAssistant::ReplyJob).to receive(:perform_later).and_return(false)
    allow(AiAssistant::Stream).to receive(:broadcast_message).and_raise(RuntimeError, "stream down")
    expect(handoff).to have_attributes(success?: false)
    expect(generation.reload.status).to eq("failed")
    expect(conversation.reload.current_generation_id).to be_nil
    expect(conversation.messages.where(role: "assistant", status: "failed").count).to eq(1)
  end

  it "does not duplicate the terminal response on repeated refused handoffs" do
    allow(AiAssistant::ReplyJob).to receive(:perform_later).and_return(false)
    2.times { handoff }
    expect(generation.reload.status).to eq("failed")
    expect(conversation.messages.where(role: "assistant", status: "failed").count).to eq(1)
  end

  it "does not close or publish idle state for a generation replaced during enqueue" do
    replacement = nil
    allow(AiAssistant::ReplyJob).to receive(:perform_later).with(generation.id) do
      replacement_message = create(
        :ai_assistant_message,
        customer: customer,
        conversation: conversation,
        body: "Replacement"
      )
      replacement = AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: replacement_message
      )
      false
    end

    result = handoff

    expect(result).to have_attributes(success?: false, failure_code: "enqueue_failed")
    expect(generation.reload.status).to eq("superseded")
    expect(conversation.reload.current_generation).to eq(replacement)
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      .with(
        anything,
        hash_including(
          target: AiAssistant::Stream::RUNNING_ID,
          html: include('data-running="false"')
        )
      )
  end
end
