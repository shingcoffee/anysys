# frozen_string_literal: true

module AiAssistant
  module Activities
    # Marks the current assistant generation as cancelled for one thread.
    class CancelReply
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :conversation, :record
      end

      def self.call(customer:, user:, conversation_id: nil)
        new(customer: customer, user: user, conversation_id: conversation_id).call
      end

      def initialize(customer:, user:, conversation_id: nil)
        @customer = customer
        @user = user
        @conversation_id = conversation_id
      end

      def call
        # Read-only resolution: a stop that arrives after the thread is gone
        # must not resurrect it just to report that there is nothing to stop.
        conversation = existing_conversation(conversation_id)
        return not_found_failure if conversation.nil? && conversation_id.present?
        return success_result(nil) if conversation.nil?

        generation = AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
        if generation
          AiAssistant::Stream.broadcast_status(conversation, I18n.t("ai_assistant.assistant.status.stopping"))
        else
          # Nothing was live, so the panel that asked to stop is showing Stop
          # over a turn that already ended. Without this it would sit unusable
          # until its own watchdog fires minutes later.
          publish_idle(conversation)
        end
        success_result(conversation)
      end

      private

      attr_reader :customer, :user, :conversation_id

      def publish_idle(conversation)
        AiAssistant::Stream.broadcast_running(conversation, false)
        AiAssistant::Stream.broadcast_status(conversation, "")
      end
    end
  end
end
