# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ReconcileGenerationsJob, type: :job do
  describe "#perform" do
    it "delegates to AiAssistant::Cron::ReconcileGenerations.call" do
      expect(AiAssistant::Cron::ReconcileGenerations).to receive(:call)

      described_class.new.perform
    end

    it "is enqueued on the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "recovers a stranded turn end-to-end when performed" do
      customer = create(:customer)
      user = create(:user, :admin, customer: customer)
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      message = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Prompt")
      Current.customer = customer
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: message
      )
      AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
      generation.update_columns(started_at: (AiAssistant::Generation::MAX_RUNNING_AGE + 1.minute).ago)

      described_class.perform_now

      expect(generation.reload).to have_attributes(status: "failed", failure_code: "timed_out")
      expect(conversation.reload.current_generation_id).to be_nil
      expect(conversation.messages.where(role: "assistant").last.body)
        .to eq(I18n.t("ai_assistant.assistant.reply_timed_out"))
    end
  end
end
