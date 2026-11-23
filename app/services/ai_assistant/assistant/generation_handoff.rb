# frozen_string_literal: true

module AiAssistant
  module Assistant
    class GenerationHandoff
      FAILURE_CODE = "enqueue_failed"
      LOG_TAG = "[ai_assistant.generation_handoff]"

      Result = Struct.new(:success?, :failure_code, keyword_init: true)

      def self.call(generation:)
        new(generation: generation).call
      end

      def initialize(generation:)
        @generation = generation
      end

      def call
        return Result.new(success?: true) if enqueued?(enqueue)

        fail_generation
        Result.new(success?: false, failure_code: FAILURE_CODE)
      end

      private

      attr_reader :generation

      def enqueue
        AiAssistant::ReplyJob.perform_later(generation.id)
      rescue StandardError => e
        Rails.logger.error(
          "#{LOG_TAG} enqueue failed generation=#{generation.id}: #{e.class}: #{e.message}"
        )
        false
      end

      def enqueued?(job)
        return false if job == false || job.nil?
        return job.successfully_enqueued? if job.respond_to?(:successfully_enqueued?)

        true
      end

      def fail_generation
        conversation = generation.conversation
        message = nil
        pointer_cleared = conversation.with_lock do
          generation.reload
          next false unless AiAssistant::Generation::ACTIVE_STATUSES.include?(generation.status)

          message = conversation.messages.create!(
            customer_id: conversation.customer_id, role: "assistant", status: "failed",
            body: I18n.t("ai_assistant.assistant.reply_failed"),
            metadata: { "generation_id" => generation.id, "failure_code" => FAILURE_CODE }
          )
          AiAssistant::Assistant::GenerationLifecycle.finish!(
            generation, status: :failed, failure_code: FAILURE_CODE
          )
        end
        AiAssistant::Stream.broadcast_message(message) if message
        publish_idle if pointer_cleared
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} failure publication failed generation=#{generation.id}: #{e.class}: #{e.message}")
        # The transaction above rolls back together if the message could not
        # be stored. Reconciliation can recover that durable active row.
        raise unless generation.reload.status == "failed"
      end

      def publish_idle
        conversation = generation.conversation
        AiAssistant::Stream.broadcast_running(conversation, false)
        AiAssistant::Stream.broadcast_status(conversation, "")
      end
    end
  end
end
