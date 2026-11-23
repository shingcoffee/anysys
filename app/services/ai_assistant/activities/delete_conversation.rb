# frozen_string_literal: true

module AiAssistant
  module Activities
    # Removes a thread and everything in it.
    #
    # The in-flight generation is cancelled BEFORE the row goes: the reply job
    # re-reads its generation between vendor calls and stops when it is gone
    # (see AiAssistant::Activities::Reply), so cancelling first is what keeps a
    # running turn from writing entities into a thread that no longer exists.
    class DeleteConversation
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :conversation, :record
      end

      def self.call(customer:, user:, conversation_id:)
        new(customer: customer, user: user, conversation_id: conversation_id).call
      end

      def initialize(customer:, user:, conversation_id:)
        @customer = customer
        @user = user
        @conversation_id = conversation_id
      end

      def call
        failure = preflight_failure
        return failure if failure

        conversation = resolve_named_conversation(conversation_id)
        return not_found_failure unless conversation

        AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
        conversation.destroy!
        broadcast_conversations
        success_result(conversation, http_status: 200)
      end

      private

      attr_reader :customer, :user, :conversation_id
    end
  end
end
