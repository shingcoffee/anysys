# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::SendMessage do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  def send_body(text = "Hello there")
    described_class.call(customer: customer, user: user, body: text)
  end

  before do
    Current.customer = customer
    enable_ai_assistant!(customer)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  it "persists a user message, broadcasts it, and enqueues ReplyJob" do
    result = nil
    expect { result = send_body }.to have_enqueued_job(AiAssistant::ReplyJob)
    generation = result.message.conversation.reload.current_generation
    expect(result.success?).to eq(true)
    expect(result.http_status).to eq(202)
    expect(result.message.role).to eq("user")
    expect(result.message.body).to eq("Hello there")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
    expect(generation).to have_attributes(
      user_message: result.message,
      status: "queued"
    )
    expect(AiAssistant::ReplyJob).to have_been_enqueued.with(generation.id)
    # Two replaces now: the running flag on the thread stream and the sidebar
    # on the user stream.
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(anything, hash_including(target: AiAssistant::Stream::RUNNING_ID))
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(anything, hash_including(target: AiAssistant::Stream::CONVERSATIONS_ID))
    expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
  end

  it "enqueues the generation even when the user-message broadcast fails" do
    allow(AiAssistant::Stream).to receive(:broadcast_message)
      .and_raise(RuntimeError, "no turbo")
    allow(Rails.logger).to receive(:error)

    result = nil
    expect { result = send_body }.to have_enqueued_job(AiAssistant::ReplyJob)

    generation = result.message.conversation.reload.current_generation
    expect(result.success?).to eq(true)
    expect(generation).to have_attributes(status: "queued", user_message: result.message)
    expect(AiAssistant::ReplyJob).to have_been_enqueued.with(generation.id)
    expect(Rails.logger).to have_received(:error).with(
      /message broadcast failed.*RuntimeError: no turbo/
    )
  end

  it "attaches images and uses the attached-image body when text is blank" do
    result = described_class.call(customer: customer, user: user, body: "  ", images: [ png_upload ])
    expect(result.success?).to eq(true)
    expect(result.message.body).to eq(I18n.t("ai_assistant.assistant.attached_images"))
    expect(result.message.images).to be_attached
  end

  it "never constructs OpenAI::Client" do
    expect(OpenAI::Client).not_to receive(:new)
    send_body
  end

  it "returns a failure result when the generation enqueue is refused" do
    allow(AiAssistant::ReplyJob).to receive(:perform_later).and_return(false)

    result = send_body

    expect(result).to have_attributes(
      success?: false,
      message: nil,
      http_status: 503,
      error_code: "enqueue_failed"
    )
    expect(result.errors).to contain_exactly(I18n.t("ai_assistant.assistant.reply_failed"))
    terminal = AiAssistant::Message.where(role: "assistant").sole
    expect(terminal).to have_attributes(status: "failed", body: I18n.t("ai_assistant.assistant.reply_failed"))
    expect(AiAssistant::Activities::ListMessages.call(customer: customer, user: user).pending_reply).to eq(false)
  end

  it "rolls back the user turn and conversation activity when generation installation fails" do
    conversation = create(:ai_assistant_conversation, customer: customer, user: user)
    activity = conversation.last_active_at
    allow(AiAssistant::Assistant::GenerationLifecycle).to receive(:start!).and_raise(ActiveRecord::StatementInvalid, "install failed")

    expect { send_body }.to raise_error(ActiveRecord::StatementInvalid)
    expect(conversation.reload.messages).to be_empty
    expect(conversation.last_active_at).to eq(activity)
    expect(conversation.current_generation_id).to be_nil
  end

  it "installs each generation under the same transaction and lock as its user turn" do
    allow(AiAssistant::Assistant::GenerationLifecycle).to receive(:start!).and_wrap_original do |original, **args|
      expect(AiAssistant::Conversation.connection.transaction_open?).to eq(true)
      message = args.fetch(:user_message)
      expect(args.fetch(:conversation).messages.order(:id).last).to eq(message)
      original.call(**args)
    end
    first = send_body("first").message
    first_generation = first.conversation.reload.current_generation
    second = send_body("second").message
    expect(first_generation.reload.status).to eq("superseded")
    expect(second.conversation.reload.current_generation.user_message_id).to eq(second.id)
  end

  it "deduplicates assistant routing with a stable clip key even after a newer turn arrives" do
    conversation = create(:ai_assistant_conversation, customer: customer, user: user)
    args = { customer: customer, user: user, body: "dictation", conversation_id: conversation.id,
             idempotency_key: "speech_to_text:clip:99" }
    first = described_class.call(**args).message
    newer = send_body("typed afterwards").message
    pointer = conversation.reload.current_generation_id

    expect { expect(described_class.call(**args).message).to eq(first) }
      .not_to change(AiAssistant::Message, :count)
    expect(conversation.reload.current_generation_id).to eq(pointer)
    expect(conversation.current_generation.user_message_id).to eq(newer.id)
  end

  it "enqueues after any conversation chrome broadcast raises" do
    allow(AiAssistant::Stream).to receive(:broadcast_conversations).and_raise(RuntimeError, "chrome down")
    allow(AiAssistant::Stream).to receive(:broadcast_running).and_raise(RuntimeError, "chrome down")
    expect { expect(send_body).to be_success }.to have_enqueued_job(AiAssistant::ReplyJob)
  end

  it "returns 422 when the body is blank" do
    result = send_body("  ")
    expect(result.http_status).to eq(422)
    expect(AiAssistant::Message.count).to eq(0)
  end

  it "returns 403 when the module is not enabled" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all
    expect(send_body.http_status).to eq(403)
  end

  it "returns 403 when only a transcribe assignee is configured" do
    AiAssistant::ProviderSettings.update_all(generation_active: false)
    expect(send_body.http_status).to eq(403)
  end

  it "accepts messages when only a generation assignee is configured" do
    AiAssistant::ProviderSettings.update_all(transcribe_active: false)
    expect(send_body.http_status).to eq(202)
  end

  # Regression: the old limiter used Rails.cache#increment, which never seeds a
  # missing key, so the cap could not fire in any environment. These examples
  # drive the real limiter rather than a stub.
  describe "throttling" do
    let(:burst) { AiAssistant::Limits::BURST }
    let(:sustained) { AiAssistant::Limits::SUSTAINED }

    # Both windows bucket on their own period, so the clock is pinned well
    # inside an hour: advancing past the burst window must never also roll the
    # sustained window over.
    around do |example|
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) { example.run }
    end

    # Spends one full burst window, then steps into the next one.
    def send_burst(count = burst.limit)
      statuses = Array.new(count) { send_body.http_status }
      travel(burst.period + 1.second)
      statuses
    end

    it "allows exactly BURST messages in a window and rejects the next one" do
      burst.limit.times { |i| expect(send_body.http_status).to eq(202), "call #{i + 1} should have been accepted" }

      expect(send_body.http_status).to eq(429)
      expect(AiAssistant::Message.count).to eq(burst.limit)
    end

    it "reports the burst breach distinctly from the sustained one" do
      burst.limit.times { send_body }

      expect(send_body.errors.join).to eq(I18n.t("ai_assistant.errors.rate_limited_burst"))
    end

    it "lets the admin continue once the burst window rolls over" do
      send_burst

      expect(send_body.http_status).to eq(202)
    end

    it "allows exactly SUSTAINED messages an hour and rejects the next one" do
      (sustained.limit / burst.limit).times { expect(send_burst).to all(eq(202)) }

      over = send_body
      expect(over.http_status).to eq(429)
      expect(over.errors.join).to eq(I18n.t("ai_assistant.errors.rate_limited"))
      expect(AiAssistant::Message.count).to eq(sustained.limit)
    end

    it "keeps a separate quota from the transcription limiter" do
      burst.limit.times { send_body }
      expect(send_body.http_status).to eq(429)

      enqueued = SpeechToText::Activities::EnqueueTranscription.call(
        customer: customer, user: user,
        audio: SpeechToTextAudioFixtures.upload,
        field_dom_id: "entity_entry_title", duration_seconds: 5
      )
      expect(enqueued.http_status).to eq(202)
    end
  end

  describe "conversation round cap" do
    it "rejects a send once the thread has spent its rounds" do
      conversation = current_ai_assistant_conversation(customer, user)
      AiAssistant::Limits::MAX_TURNS.times do
        create(:ai_assistant_message, conversation: conversation, customer: customer)
      end

      result = send_body

      expect(result.http_status).to eq(429)
      expect(result.errors.join).to include(AiAssistant::Limits::MAX_TURNS.to_s)
    end

    it "counts only the admin's own turns, not the assistant's replies" do
      conversation = current_ai_assistant_conversation(customer, user)
      AiAssistant::Limits::MAX_TURNS.times do
        create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer)
      end

      expect(send_body.http_status).to eq(202)
    end

    it "lets the admin continue in a thread started after the cap was spent" do
      conversation = current_ai_assistant_conversation(customer, user)
      AiAssistant::Limits::MAX_TURNS.times do
        create(:ai_assistant_message, conversation: conversation, customer: customer)
      end
      expect(send_body.http_status).to eq(429)

      started = AiAssistant::Activities::StartConversation.call(customer: customer, user: user)

      expect(send_body.http_status).to eq(202)
      expect(AiAssistant::Message.where(conversation_id: started.conversation.id)).to exist
    end

    # The cap is re-counted while the conversation row is locked, so two
    # parallel sends cannot both take the last round. Standing in for the race:
    # the early check is blinded, leaving the locked claim as the only guard.
    it "enforces the cap at the insert, not only in the early check" do
      conversation = current_ai_assistant_conversation(customer, user)
      AiAssistant::Limits::MAX_TURNS.times do
        create(:ai_assistant_message, conversation: conversation, customer: customer)
      end
      # Blinds the pre-write check only. The activity resolves the thread again
      # inside the lock, which is the guard under test.
      allow_any_instance_of(described_class).to receive(:target_conversation).and_return(nil)

      result = send_body

      expect(result.http_status).to eq(429)
      expect(result.error_code).to eq("conversation_limit")
      expect(conversation.reload.user_turns).to eq(AiAssistant::Limits::MAX_TURNS)
    end
  end

  describe "conversation scoping" do
    it "sends into the named thread rather than the most recent one" do
      older = create(:ai_assistant_conversation, customer: customer, user: user)
      create(:ai_assistant_conversation, customer: customer, user: user)

      result = described_class.call(
        customer: customer, user: user, body: "into the old one",
        conversation_id: older.id
      )

      expect(result.success?).to eq(true)
      expect(result.message.conversation_id).to eq(older.id)
    end

    it "returns 404 for another user's thread in the same tenant" do
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)

      result = described_class.call(
        customer: customer, user: user, body: "hi", conversation_id: foreign.id
      )

      expect(result.http_status).to eq(404)
      expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
      expect(foreign.reload.messages).to be_empty
    end

    it "returns 404 for the same user's thread in another tenant" do
      other_tenant = create(:customer)
      cross = create(:user, :admin, customer: other_tenant)
      foreign = create(:ai_assistant_conversation, customer: other_tenant, user: cross)

      result = described_class.call(
        customer: customer, user: user, body: "hi", conversation_id: foreign.id
      )

      expect(result.http_status).to eq(404)
      expect(foreign.reload.messages).to be_empty
    end

    it "names a new thread after its opening prompt and bumps its activity" do
      result = described_class.call(
        customer: customer, user: user, body: "  Build me a  Student entity  "
      )
      conversation = result.message.conversation.reload

      expect(conversation.title).to eq("Build me a Student entity")
      expect(conversation.last_active_at).to be_within(5.seconds).of(Time.current)
    end

    it "truncates an over-long opening prompt to the title limit" do
      result = described_class.call(customer: customer, user: user, body: "w" * 200)

      expect(result.message.conversation.reload.title.length)
        .to eq(AiAssistant::Conversation::TITLE_LIMIT)
    end

    it "leaves a thread the user already named alone" do
      conversation = create(
        :ai_assistant_conversation, customer: customer, user: user, title: "Budget review"
      )

      described_class.call(
        customer: customer, user: user, body: "something else", conversation_id: conversation.id
      )

      expect(conversation.reload.title).to eq("Budget review")
    end

    it "refuses a send before creating a thread when the module is disabled" do
      fm = FeatureModules::Module.find_by!(key: "ai_assistant")
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

      expect { send_body }.not_to change(AiAssistant::Conversation, :count)
    end

    it "refreshes the sidebar for the sending user" do
      allow(AiAssistant::Stream).to receive(:broadcast_conversations)

      result = send_body

      expect(AiAssistant::Stream).to have_received(:broadcast_conversations).with(
        customer: customer, user: user, current_id: result.message.conversation_id
      )
    end
  end

  describe "empty-state removal" do
    it "removes the dashboard empty state only for the first turn of a thread" do
      send_body("first")
      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to)
        .with(anything, hash_including(target: AiAssistant::Stream::EMPTY_ID)).once

      send_body("second")
      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to)
        .with(anything, hash_including(target: AiAssistant::Stream::EMPTY_ID)).once
    end
  end

  describe "proposal_message_id" do
    it "stores a positive integer as confirms_message_id" do
      result = described_class.call(
        customer: customer, user: user, body: "yes", proposal_message_id: 12
      )

      expect(result.success?).to eq(true)
      expect(result.message.metadata_json).to eq("confirms_message_id" => 12)
    end

    it "stores a numeric string as an integer id" do
      result = described_class.call(
        customer: customer, user: user, body: "yes", proposal_message_id: "34"
      )

      expect(result.message.metadata_json.fetch("confirms_message_id")).to eq(34)
    end

    it "reads a numeric string as decimal, never octal or hex" do
      decimal = described_class.call(customer: customer, user: user, body: "yes", proposal_message_id: "012")
      hex = described_class.call(customer: customer, user: user, body: "yes", proposal_message_id: "0x1A")

      expect(decimal.message.metadata_json.fetch("confirms_message_id")).to eq(12)
      expect(hex.message.metadata_json).not_to have_key("confirms_message_id")
    end

    it "keeps confirms_message_id alongside an idempotency_key" do
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      result = described_class.call(
        customer: customer, user: user, body: "yes",
        conversation_id: conversation.id,
        idempotency_key: "speech_to_text:clip:1",
        proposal_message_id: 9
      )

      expect(result.message.metadata_json).to eq(
        "idempotency_key" => "speech_to_text:clip:1",
        "confirms_message_id" => 9
      )
    end

    it "ignores a non-positive integer" do
      result = described_class.call(
        customer: customer, user: user, body: "yes", proposal_message_id: 0
      )

      expect(result.message.metadata_json).not_to have_key("confirms_message_id")
    end

    it "ignores a non-numeric value" do
      result = described_class.call(
        customer: customer, user: user, body: "yes", proposal_message_id: "yes"
      )

      expect(result.message.metadata_json).not_to have_key("confirms_message_id")
    end
  end
end
