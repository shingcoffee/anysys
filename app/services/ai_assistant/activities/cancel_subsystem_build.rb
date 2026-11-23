# frozen_string_literal: true

module AiAssistant
  module Activities
    # Cancel on a sub-system build. The build is reached only through a reply
    # in a conversation the caller owns, and only when it belongs to that same
    # conversation. The running job stops at its next item; what it already
    # built stays. Spends no turn and makes no vendor call.
    class CancelSubsystemBuild
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
        build = message && owned_build(message)
        return not_found_failure unless build

        cancelled = build.with_lock { build.active? && build.update!(status: "cancelled") }
        unless cancelled
          return Result.new(success?: false, record: message, http_status: 422,
                            errors: [I18n.t("ai_assistant.subsystems.cancel.not_active")])
        end

        broadcast(message, build)
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

      def owned_build(message)
        AiAssistant::SubsystemBuild.unscoped.find_by(
          id: message.metadata_json.dig("subsystem_build", "id"),
          customer_id: customer.id,
          conversation_id: message.conversation_id
        )
      end

      def broadcast(message, build)
        message.conversation.messages.where("json_extract(metadata, '$.subsystem_build.id') = ?", build.id)
               .find_each { |shown| AiAssistant::Stream.broadcast_message_replace(shown) }
      rescue StandardError => e
        Rails.logger.error("[ai_assistant.cancel_subsystem_build] broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
