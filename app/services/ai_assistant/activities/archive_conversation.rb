# frozen_string_literal: true

module AiAssistant
  module Activities
    # Moves a thread between the open list and the archived one. Archiving is
    # the non-destructive alternative to DeleteConversation: the turns stay
    # readable, the thread just stops being a candidate for "the current one"
    # (AiAssistant::Conversation.current_for only looks at the active scope).
    class ArchiveConversation
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :conversation, :record
      end

      def self.call(customer:, user:, conversation_id:, archived:)
        new(customer: customer, user: user, conversation_id: conversation_id, archived: archived).call
      end

      def initialize(customer:, user:, conversation_id:, archived:)
        @customer = customer
        @user = user
        @conversation_id = conversation_id
        @archived = archived
      end

      def call
        failure = preflight_failure
        return failure if failure

        conversation = resolve_named_conversation(conversation_id)
        return not_found_failure unless conversation

        # A turn still running would keep streaming into a thread the sidebar
        # has just put away, and would finally write its reply somewhere the
        # user can only reach through the archived disclosure.
        AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation) if archived?
        archived? ? conversation.archive! : conversation.unarchive!
        # An archived thread is no longer the current one, so the sidebar is
        # told to highlight nothing rather than a row it just moved away.
        broadcast_conversations(current_id: conversation.archived? ? nil : conversation.id)
        success_result(conversation, http_status: 200)
      end


      private

      attr_reader :customer, :user, :conversation_id

      # The flag arrives as a JSON boolean from the sidebar and as a string
      # from a form post, so it is cast rather than tested for truthiness.
      def archived?
        ActiveModel::Type::Boolean.new.cast(@archived).present?
      end
    end
  end
end
