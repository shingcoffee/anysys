# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::RegenerateLast do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  before do
    Current.customer = customer
    enable_ai_assistant!(customer)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    Authentication::Throttle.reset_store!
  end

  it "enqueues ReplyJob for the last user turn on this user's thread" do
    conversation = current_ai_assistant_conversation(customer, user)
    older = create(:ai_assistant_message, conversation: conversation, customer: customer, body: "older")
    last = create(:ai_assistant_message, conversation: conversation, customer: customer, body: "latest")
    create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer)
    result = nil
    expect { result = described_class.call(customer: customer, user: user) }.to have_enqueued_job(AiAssistant::ReplyJob)
    generation = conversation.reload.current_generation
    expect(result.success?).to eq(true)
    expect(generation).to have_attributes(user_message: last, status: "queued")
    expect(AiAssistant::ReplyJob).to have_been_enqueued.with(generation.id)
    expect(generation.user_message).not_to eq(older)
  end

  it "returns 422 when the thread has no user turn" do
    result = described_class.call(customer: customer, user: user)
    expect(result.http_status).to eq(422)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.nothing_to_regenerate"))
  end

  # Regression: this used the creating resolver, so replaying a turn for a user
  # who had no thread minted one — a write from a request that had nothing to
  # replay. It now reads through the read-only resolver.
  it "creates no thread for a user who has never chatted" do
    result = nil

    expect { result = described_class.call(customer: customer, user: user) }
      .not_to change(AiAssistant::Conversation, :count)

    expect(result.http_status).to eq(422)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.nothing_to_regenerate"))
  end

  it "creates no thread when the named id resolves to nothing" do
    result = nil

    expect { result = described_class.call(customer: customer, user: user, conversation_id: 999_999) }
      .not_to change(AiAssistant::Conversation, :count)

    expect(result.http_status).to eq(404)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
  end

  it "replays the running thread rather than the most recently active idle one" do
    idle = create(:ai_assistant_conversation, customer: customer, user: user, last_active_at: 1.minute.ago)
    create(:ai_assistant_message, conversation: idle, customer: customer, body: "idle turn")
    running = create(:ai_assistant_conversation, customer: customer, user: user, last_active_at: 3.days.ago)
    last = create(:ai_assistant_message, conversation: running, customer: customer, body: "running turn")
    AiAssistant::Assistant::GenerationLifecycle.start!(conversation: running, user_message: last)

    described_class.call(customer: customer, user: user)

    expect(running.reload.current_generation.user_message).to eq(last)
    expect(idle.reload.current_generation).to be_nil
  end

  it "returns a failure result when the generation enqueue raises" do
    conversation = current_ai_assistant_conversation(customer, user)
    create(
      :ai_assistant_message,
      conversation: conversation,
      customer: customer,
      body: "latest"
    )
    allow(AiAssistant::ReplyJob).to receive(:perform_later)
      .and_raise(ActiveJob::EnqueueError, "queue unavailable")

    result = described_class.call(customer: customer, user: user)

    expect(result).to have_attributes(
      success?: false,
      message: nil,
      http_status: 503,
      error_code: "enqueue_failed"
    )
    expect(result.errors).to contain_exactly(I18n.t("ai_assistant.assistant.reply_failed"))
  end

  it "does not enqueue for another user in the same tenant" do
    other = create(:user, :admin, customer: customer)
    conversation = current_ai_assistant_conversation(customer, other)
    create(:ai_assistant_message, conversation: conversation, customer: customer, body: "secret")
    expect { described_class.call(customer: customer, user: user) }.not_to have_enqueued_job(AiAssistant::ReplyJob)
  end

  it "regenerates the named thread rather than the most recent one" do
    older = create(:ai_assistant_conversation, customer: customer, user: user)
    last = create(:ai_assistant_message, conversation: older, customer: customer, body: "older turn")
    create(:ai_assistant_conversation, customer: customer, user: user)

    described_class.call(customer: customer, user: user, conversation_id: older.id)

    expect(older.reload.current_generation.user_message).to eq(last)
  end

  it "returns 404 for another user's thread" do
    other = create(:user, :admin, customer: customer)
    foreign = create(:ai_assistant_conversation, customer: customer, user: other)
    create(:ai_assistant_message, conversation: foreign, customer: customer, body: "secret")

    result = described_class.call(customer: customer, user: user, conversation_id: foreign.id)

    expect(result.http_status).to eq(404)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
    expect(foreign.reload.current_generation).to be_nil
  end

  it "returns 404 for the same user's thread in another tenant" do
    other_tenant = create(:customer)
    cross = create(:user, :admin, customer: other_tenant)
    foreign = create(:ai_assistant_conversation, customer: other_tenant, user: cross)
    create(:ai_assistant_message, conversation: foreign, customer: other_tenant, body: "secret")

    result = described_class.call(customer: customer, user: user, conversation_id: foreign.id)

    expect(result.http_status).to eq(404)
    expect(foreign.reload.current_generation).to be_nil
  end
end
