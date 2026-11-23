# frozen_string_literal: true

module AiAssistant
  module Activities
    # Discard on a pending proposal. The reply is reached only through a
    # conversation the caller owns, and the decline runs under the
    # conversation row lock, the same lock a generation holds while it
    # writes, so a discard never interleaves with consume. Spends no turn
    # and makes no vendor call.
    class DiscardProposal
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :message, :record
      end

      def self.call(customer:, user:, message_id:)
        new(customer: customer, user: user, message_id: message_id).call
      end

      def initialize(customer:, user:, message_id:)
        @customer = customer
        @user = user
        @message_id = message_id
      end

      def call
        failure = preflight_failure
        return failure if failure

        message = owned_reply
        return not_found_failure unless message

        declined = message.conversation.with_lock do
          AiAssistant::Assistant::PendingConfirmation.decline!(message.reload, actor: user)
        end
        unless declined
          return Result.new(
            success?: false,
            record: message,
            http_status: 422,
            errors: [ I18n.t("ai_assistant.assistant.proposal_not_pending") ]
          )
        end

        broadcast(message)
        success_result(message, http_status: 200)
      end

      private

      attr_reader :customer, :user, :message_id

      def owned_reply
        AiAssistant::Message
          .where(customer_id: customer.id, role: "assistant")
          .where(conversation_id: AiAssistant::Conversation.owned_by(customer: customer, user: user).select(:id))
          .find_by(id: message_id)
      end

      def broadcast(message)
        AiAssistant::Stream.broadcast_message_replace(message)
      rescue StandardError => e
        Rails.logger.error("[ai_assistant.discard_proposal] broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
