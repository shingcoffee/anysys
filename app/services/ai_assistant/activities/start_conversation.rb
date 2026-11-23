# frozen_string_literal: true

module AiAssistant
  module Activities
    # "New chat". Replaces the old ResetConversation: a fresh thread is added
    # to the list instead of the only existing one being wiped, so the round
    # cap (AiAssistant::Limits::MAX_TURNS) is escaped without losing history.
    class StartConversation
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :conversation, :record
      end

      def self.call(customer:, user:)
        new(customer: customer, user: user).call
      end

      def initialize(customer:, user:)
        @customer = customer
        @user = user
      end

      def call
        failure = preflight_failure
        return failure if failure
        conversation = user.with_lock do
          return capacity_failure if at_capacity?
          return empty_chat_failure if current_chat_empty?

          AiAssistant::Conversation.start_for(customer: customer, user: user)
        end
        broadcast_conversations(current_id: conversation.id)
        success_result(conversation, http_status: 201)
      end

      private

      attr_reader :customer, :user

      def at_capacity?
        AiAssistant::Conversation.at_capacity?(customer: customer, user: user)
      end

      # Starting a second chat from an unused one only produces two identical
      # blank threads, so the unused one is the answer to "I want a new chat".
      # Read-only on purpose: Conversation.current_for would mint the very row
      # this refuses to duplicate.
      def current_chat_empty?
        chat = AiAssistant::Conversation.owned_by(customer: customer, user: user)
                                        .active.recent_first.first

        chat.present? && chat.empty?
      end

      # 422, not 429: nothing has been spent, the request just has nothing to
      # do — the chat the caller wants is already open in front of them.
      def empty_chat_failure
        fail_result(
          422,
          [ I18n.t("ai_assistant.errors.current_chat_empty") ],
          error_code: "current_chat_empty"
        )
      end

      # 429 rather than 422: the ceiling is a quota, and the composer already
      # treats 429 as "you have spent an allowance", not "your input is wrong".
      def capacity_failure
        fail_result(
          429,
          [ I18n.t("ai_assistant.errors.conversation_count_limit",
                   count: AiAssistant::Conversation::MAX_PER_USER) ],
          error_code: "conversation_count_limit"
        )
      end
    end
  end
end
