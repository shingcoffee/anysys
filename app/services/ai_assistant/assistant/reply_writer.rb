# frozen_string_literal: true

module AiAssistant
  module Assistant
    class ReplyWriter
      LOG_TAG = "[ai_assistant.reply_writer]"

      def self.call(conversation:, finalized:, write_guard: nil,
                    required_status: "running")
        new(
          conversation: conversation,
          finalized: finalized,
          write_guard: write_guard,
          required_status: required_status
        ).call
      end

      def initialize(conversation:, finalized:, write_guard:, required_status:)
        @conversation = conversation
        @finalized = finalized
        @write_guard = write_guard
        @required_status = required_status
      end

      def call
        message = persist
        broadcast_message(message)
        broadcast_artifact if @finalized.artifact
        message
      end

      private

      def persist
        operation = lambda do
          @conversation.transaction(requires_new: true) do
            # A thread may offer at most one proposal at a time. Retired in
            # the same transaction that parks the new one, so there is no
            # moment in which two are applicable and no way for the write to
            # succeed while the retirement is rolled back.
            PendingConfirmation.retire_open!(@conversation) if parking_proposal?

            message = @conversation.messages.create!(
              customer_id: @conversation.customer_id,
              role: "assistant",
              body: @finalized.body,
              status: @finalized.status,
              metadata: @finalized.metadata
            )
            Artifact.assign_record!(
              @conversation,
              record: @finalized.artifact
            ) if @finalized.artifact
            message
          end
        end
        return operation.call unless @write_guard

        @write_guard.call(required_status: @required_status, &operation)
      end

      def parking_proposal?
        metadata = @finalized.metadata
        metadata.is_a?(Hash) && metadata["pending_confirmation"].present?
      end

      def broadcast_artifact
        AiAssistant::Stream.broadcast_artifact(@conversation)
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} artifact broadcast failed: #{e.class}: #{e.message}")
      end

      def broadcast_message(message)
        AiAssistant::Stream.broadcast_message(message)
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} message broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
