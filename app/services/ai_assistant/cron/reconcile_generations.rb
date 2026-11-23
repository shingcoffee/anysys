# frozen_string_literal: true

module AiAssistant
  module Cron
    # Recovers turns whose reply job died (worker crash, deploy) or was never
    # picked up. Nothing else terminalizes them: the generation stays active,
    # the conversation keeps pointing at it, and every session except the
    # sender's own tab keeps a half-written draft and a "Thinking…" pill for
    # good — an id-less Stop or Regenerate then keeps selecting that dead
    # thread.
    #
    # Each row is claimed with one conditional UPDATE, so this is safe to run
    # concurrently with itself and with a live turn. Cross-tenant by design (no
    # Current.customer).
    class ReconcileGenerations
      LOG_TAG = "[ai_assistant.reconcile_generations]"

      def self.call
        new.call
      end

      def call
        AiAssistant::Generation.stalled.find_each do |generation|
          I18n.with_locale(
            AiAssistant::Locale.for(
              user: generation.conversation.user,
              customer: generation.customer
            )
          ) { reconcile(generation) }
        rescue StandardError => e
          Rails.logger.warn("#{LOG_TAG} reconcile failed generation=#{generation.id}: #{e.class}: #{e.message}")
        end
      end

      private

      def reconcile(generation)
        stale_status = generation.status
        return unless AiAssistant::Generation.time_out!(generation.id)

        Rails.logger.warn("#{LOG_TAG} timed out generation=#{generation.id} was=#{stale_status}")
        conversation = generation.conversation
        write_failure_bubble(conversation)
        publish_idle(conversation) if release_pointer(generation)
      end

      # The same bubble an expected failure leaves, so the thread reads as a
      # turn that failed rather than as a prompt that was never answered. It is
      # best-effort: the row has already been claimed, so a bubble that cannot
      # be written must not cost the thread its pointer release too.
      def write_failure_bubble(conversation)
        AiAssistant::Assistant::ReplyWriter.call(
          conversation: conversation,
          finalized: AiAssistant::Assistant::Finalizer::Result.new(
            body: I18n.t("ai_assistant.assistant.reply_timed_out"),
            status: "failed",
            metadata: { "changes" => [] }
          )
        )
      rescue StandardError => e
        Rails.logger.warn(
          "#{LOG_TAG} bubble not written conversation=#{conversation.id}: #{e.class}: #{e.message}"
        )
      end

      # The status transition is already done, so this only clears the
      # conversation pointer — and only while it still names this generation,
      # which is what keeps a turn started in the meantime intact.
      def release_pointer(generation)
        AiAssistant::Assistant::GenerationLifecycle.finish!(
          generation,
          status: :failed,
          failure_code: "timed_out"
        )
      end

      # An open tab is showing a draft bubble and a status pill that nothing
      # else is going to close, so a session that lived through the crash
      # recovers without a reload.
      def publish_idle(conversation)
        AiAssistant::Stream.broadcast_draft_close(conversation)
        AiAssistant::Stream.broadcast_running(conversation, false)
        AiAssistant::Stream.broadcast_status(conversation, "")
      end
    end
  end
end
