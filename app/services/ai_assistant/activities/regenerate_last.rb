# frozen_string_literal: true

module AiAssistant
  module Activities
    # Re-runs Reply for the latest user turn on one of this user's threads.
    class RegenerateLast
      include AiAssistant::Activities::ConversationScoped

      class Result < Preflight::Result
        alias_method :message, :record
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
        failure = preflight_failure
        return failure if failure

        # Read-only: replaying a turn needs a thread that already has one, so
        # there is nothing to create here. A named id that resolves to nothing
        # is a 404, but having no thread at all is "nothing to regenerate" —
        # the same answer as an empty one.
        conversation = existing_conversation(conversation_id)
        return not_found_failure if conversation.nil? && conversation_id.present?

        # A replay spends the same vendor calls a send does, so it answers to
        # the same per-thread cap. Without this a thread that renders a
        # disabled composer still runs full turns through regenerate.
        return conversation_limit_failure if exhausted?(conversation)

        last_user = conversation&.messages&.where(role: "user", status: "complete")&.order(:id)&.last
        return fail_result(422, [ I18n.t("ai_assistant.errors.nothing_to_regenerate") ]) unless last_user

        generation = AiAssistant::Assistant::GenerationLifecycle.start!(
          conversation: conversation,
          user_message: last_user
        )
        AiAssistant::Stream.broadcast_running(conversation, true)
        AiAssistant::Stream.broadcast_status(conversation, I18n.t("ai_assistant.assistant.status.thinking"))
        generation_handoff_result(generation: generation, record: last_user)
      end

      private

      attr_reader :customer, :user, :conversation_id

      # A regenerate spends a vendor call, so unlike the sidebar activities it
      # keeps Preflight's provider-configured check and throttle.
      def preflight_failure
        disabled_failure || unconfigured_failure || rate_limited_failure
      end

      def rate_scope = "chat"

      def provider_job = :generation
    end
  end
end
