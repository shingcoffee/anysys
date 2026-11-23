# frozen_string_literal: true

module AiAssistant
  module Activities
    # Undo on a reply that wrote website pages. The reply is reached only
    # through a conversation the caller owns, and the revert runs under the
    # conversation row lock, the same lock a generation holds while it writes,
    # so an undo never interleaves with a reply's own write.
    class UndoWebsiteReply
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
        unless FeatureModules::Website::Registration.enabled_for?(customer.id)
          return fail_result(403, [ I18n.t("ai_assistant.assistant.website.module_disabled") ])
        end

        message = owned_reply
        return fail_result(404, [ I18n.t("ai_assistant.assistant.website.undo.errors.unavailable") ]) unless message

        outcome = message.conversation.with_lock do
          Websites::Assistant::Undo.call(message: message.reload, customer: customer)
        end
        return Result.new(success?: false, record: message, http_status: 422, errors: outcome.errors) unless outcome.success?

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

      # Other tabs on the thread, and the preview pane, which may be showing a
      # page that was just deleted or put back. The undo has committed, so a
      # failed redraw is a stale panel, not a failed request.
      def broadcast(message)
        AiAssistant::Stream.broadcast_message_replace(message)
        AiAssistant::Stream.broadcast_artifact(message.conversation)
      rescue StandardError => e
        Rails.logger.error("[ai_assistant.undo_website_reply] broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
