# frozen_string_literal: true

module AiAssistant
  module Activities
    # Read-path for the desktop assistant: return this user's conversation
    # in the URL tenant. Never calls a vendor.
    class ListMessages
      MODULE_KEY = "ai_assistant"

      # The desktop client polls this endpoint, so an unbounded history meant
      # every poll serialized the whole conversation. Return the most recent
      # window (oldest-first) — well above PromptBuilder::HISTORY_LIMIT, which
      # is all the model ever sees anyway.
      MESSAGE_LIMIT = 100

      Result = Struct.new(:success?, :messages, :pending_reply, :http_status, :errors, keyword_init: true)

      def self.call(customer:, user:, conversation_id: nil)
        new(customer: customer, user: user, conversation_id: conversation_id).call
      end

      def initialize(customer:, user:, conversation_id: nil)
        @customer = customer
        @user = user
        @conversation_id = conversation_id
      end

      def call
        return fail_result(403, [ I18n.t("ai_assistant.errors.module_disabled") ]) unless module_enabled?
        return fail_result(403, [ I18n.t("ai_assistant.errors.unconfigured") ]) unless AiAssistant::ProviderSettings.active_for(:generation)

        conversation = resolved_conversation
        messages = conversation ? recent_messages(conversation) : []
        Result.new(
          success?: true,
          messages: messages,
          pending_reply: pending_reply?(conversation, messages),
          http_status: 200,
          errors: []
        )
      end

      private

      attr_reader :customer, :user, :conversation_id

      # A blank id has to pick the same thread the write path picks, or the
      # client's GET and its POST disagree about which thread is "the"
      # conversation as soon as the user has more than one. That is
      # Conversation.current_for's rule minus the create — this runs from a GET
      # and must not mint a row.
      def resolved_conversation
        scope = AiAssistant::Conversation.owned_by(customer: customer, user: user)
        return scope.find_by(id: conversation_id) if conversation_id.present?

        scope.active.recent_first.first
      end

      def recent_messages(conversation)
        conversation.messages.order(id: :desc).limit(MESSAGE_LIMIT).reverse
      end

      # Only a live generation is pending. A failed handoff or a historical
      # unanswered prompt must not keep a polling client spinning forever.
      def pending_reply?(conversation, messages)
        return false unless conversation

        conversation.generations.where(
          id: conversation.current_generation_id,
          status: AiAssistant::Generation::ACTIVE_STATUSES
        ).exists?
      end

      def module_enabled?
        FeatureModules::Module.enabled?(key: MODULE_KEY, customer_id: customer.id)
      end

      def fail_result(status, errors)
        Result.new(success?: false, messages: [], pending_reply: false, http_status: status, errors: Array(errors))
      end
    end
  end
end
