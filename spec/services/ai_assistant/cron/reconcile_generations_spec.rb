# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Cron::ReconcileGenerations do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  before do
    Current.customer = customer
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
  end

  # A turn whose worker died: claimed, then left `running` with a started_at
  # nobody moved again.
  def stalled_turn(thread = conversation, tenant = customer)
    live_turn(thread, tenant).tap do |generation|
      generation.update_columns(
        started_at: (AiAssistant::Generation::MAX_RUNNING_AGE + 5.minutes).ago
      )
    end
  end

  def live_turn(thread = conversation, tenant = customer)
    message = create(:ai_assistant_message, customer: tenant, conversation: thread, body: "Prompt")
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: thread,
      user_message: message
    )
    AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
    generation
  end

  def assistant_bubbles(thread)
    thread.messages.where(role: "assistant")
  end

  describe "a turn whose worker never came back" do
    it "terminalizes the generation with its own failure code" do
      generation = stalled_turn

      described_class.call

      expect(generation.reload).to have_attributes(status: "failed", failure_code: "timed_out")
      expect(generation.finished_at).to be_present
    end

    it "clears the conversation's current generation pointer" do
      stalled_turn

      described_class.call

      expect(conversation.reload.current_generation_id).to be_nil
    end

    it "leaves a translated failed bubble in the thread" do
      stalled_turn

      described_class.call

      expect(assistant_bubbles(conversation).last).to have_attributes(
        status: "failed",
        body: I18n.t("ai_assistant.assistant.reply_timed_out"),
        customer_id: customer.id
      )
    end

    it "writes the timeout bubble in the conversation user's locale" do
      user.update!(locale: "zh-CN")
      stalled_turn

      described_class.call

      expect(assistant_bubbles(conversation).last.body)
        .to eq(I18n.t("ai_assistant.assistant.reply_timed_out", locale: :"zh-CN"))
    end

    it "publishes the idle state so an open tab recovers without a reload" do
      stalled_turn

      described_class.call

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(anything, hash_including(target: AiAssistant::Stream::DRAFT_ID))
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(anything, hash_including(target: AiAssistant::Stream::RUNNING_ID))
      expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
        .with(anything, hash_including(target: AiAssistant::Stream::STATUS_ID, html: ""))
    end

    it "recovers a queued turn whose job never arrived" do
      message = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Prompt")
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: message
      )
      generation.update_columns(created_at: (AiAssistant::Generation::MAX_QUEUED_AGE + 1.minute).ago)

      described_class.call

      expect(generation.reload.status).to eq("failed")
      expect(conversation.reload.current_generation_id).to be_nil
    end
  end

  describe "a turn that is still being written" do
    it "leaves a freshly claimed generation alone" do
      generation = live_turn

      described_class.call

      expect(generation.reload.status).to eq("running")
      expect(conversation.reload.current_generation_id).to eq(generation.id)
      expect(assistant_bubbles(conversation)).to be_empty
    end

    it "leaves a queued generation inside its grace alone" do
      message = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Prompt")
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: message
      )

      described_class.call

      expect(generation.reload.status).to eq("queued")
    end

    it "leaves an already terminal generation alone" do
      generation = live_turn
      AiAssistant::Assistant::GenerationLifecycle.finish!(generation, status: :completed)
      generation.update_columns(started_at: 1.day.ago)

      described_class.call

      expect(generation.reload.status).to eq("completed")
      expect(assistant_bubbles(conversation)).to be_empty
    end
  end

  describe "running more than once" do
    it "writes exactly one bubble for the same stale turn" do
      stalled_turn

      described_class.call
      described_class.call

      expect(assistant_bubbles(conversation).count).to eq(1)
    end

    it "does not disturb a turn started after the recovery" do
      stalled_turn
      described_class.call
      replacement = live_turn

      described_class.call

      expect(replacement.reload.status).to eq("running")
      expect(conversation.reload.current_generation_id).to eq(replacement.id)
    end
  end

  describe "tenant and user isolation" do
    it "leaves another tenant's live turn untouched" do
      other_tenant = create(:customer)
      other_user = create(:user, :admin, customer: other_tenant)
      other_thread = create(:ai_assistant_conversation, customer: other_tenant, user: other_user)
      other_turn = live_turn(other_thread, other_tenant)
      stalled_turn

      described_class.call

      expect(other_turn.reload.status).to eq("running")
      expect(other_thread.reload.current_generation_id).to eq(other_turn.id)
      expect(assistant_bubbles(other_thread)).to be_empty
    end

    it "leaves another user's live turn in the same tenant untouched" do
      other_user = create(:user, :admin, customer: customer)
      other_thread = create(:ai_assistant_conversation, customer: customer, user: other_user)
      other_turn = live_turn(other_thread)
      stalled_turn

      described_class.call

      expect(other_turn.reload.status).to eq("running")
      expect(assistant_bubbles(other_thread)).to be_empty
    end

    # The reaper is cross-tenant by design: a dead worker strands turns in
    # whatever tenants it was serving, and each has to recover on its own.
    it "recovers a stale turn in every tenant, each in its own thread" do
      other_tenant = create(:customer)
      other_user = create(:user, :admin, customer: other_tenant)
      other_thread = create(:ai_assistant_conversation, customer: other_tenant, user: other_user)
      mine = stalled_turn
      theirs = stalled_turn(other_thread, other_tenant)

      described_class.call

      expect(mine.reload.status).to eq("failed")
      expect(theirs.reload.status).to eq("failed")
      expect(assistant_bubbles(conversation).count).to eq(1)
      expect(assistant_bubbles(other_thread).count).to eq(1)
      expect(assistant_bubbles(other_thread).last.customer_id).to eq(other_tenant.id)
    end
  end

  describe "when one row cannot be recovered" do
    it "still releases the thread when the bubble cannot be written" do
      generation = stalled_turn
      allow(AiAssistant::Assistant::ReplyWriter).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, "bubble failed")
      allow(Rails.logger).to receive(:warn)

      described_class.call

      expect(generation.reload.status).to eq("failed")
      expect(conversation.reload.current_generation_id).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/bubble not written/)
    end

    it "keeps recovering the remaining rows" do
      first = stalled_turn
      other_thread = create(:ai_assistant_conversation, customer: customer, user: user)
      second = stalled_turn(other_thread)
      allow(AiAssistant::Assistant::GenerationLifecycle).to receive(:finish!)
        .and_wrap_original do |original, generation, **options|
          raise ActiveRecord::StatementInvalid, "pointer failed" if generation.id == first.id

          original.call(generation, **options)
        end
      allow(Rails.logger).to receive(:warn)

      expect { described_class.call }.not_to raise_error

      expect(second.reload.status).to eq("failed")
      expect(other_thread.reload.current_generation_id).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/reconcile failed generation=#{first.id}/)
    end
  end
end
