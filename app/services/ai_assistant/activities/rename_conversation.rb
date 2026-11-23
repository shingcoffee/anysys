# frozen_string_literal: true

module AiAssistant
  module Activities
    # Names a thread from the sidebar. A renamed thread stops borrowing its
    # first prompt (AiAssistant::Conversation#adopt_title_from bails once a
    # title is set), so this is a one-way handover to the user.
    class RenameConversation
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :conversation, :record
      end

      def self.call(customer:, user:, conversation_id:, title:)
        new(customer: customer, user: user, conversation_id: conversation_id, title: title).call
      end

      def initialize(customer:, user:, conversation_id:, title:)
        @customer = customer
        @user = user
        @conversation_id = conversation_id
        @title = title
      end

      def call
        failure = preflight_failure
        return failure if failure

        conversation = resolve_named_conversation(conversation_id)
        return not_found_failure unless conversation

        conversation.update!(title: contract.normalized_title)
        broadcast_conversations(current_id: conversation.id)
        success_result(conversation, http_status: 200)
      end

      private

      attr_reader :customer, :user, :conversation_id, :title

      def contract_valid?
        contract.validate(title: title)
      end

      def contract_errors
        contract.errors.full_messages
      end

      def contract
        @contract ||= AiAssistant::Contracts::ConversationTitle.new(
          AiAssistant::Contracts::ConversationTitle::Input.new
        )
      end
    end
  end
end
