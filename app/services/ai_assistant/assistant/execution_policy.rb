# frozen_string_literal: true

module AiAssistant
  module Assistant
    class ExecutionPolicy
      Result = Struct.new(:allowed, :error_code, keyword_init: true) do
        def allowed? = allowed
      end

      def self.call(generation:)
        new(generation: generation).call
      end

      def initialize(generation:)
        @generation = generation
      end

      def call
        return denied(:invalid_context) unless context_consistent?
        return denied(:unauthorized) unless authorized_user?
        return denied(:module_disabled) unless module_enabled?
        return denied(:unconfigured) unless provider_configured?

        Result.new(allowed: true)
      end

      private

      def context_consistent?
        conversation = @generation.conversation
        message = @generation.user_message
        @generation.customer_id == conversation.customer_id &&
          message.customer_id == conversation.customer_id &&
          message.conversation_id == conversation.id &&
          message.user?
      end

      def authorized_user?
        user = @generation.conversation.user
        return false unless user.active?
        return true if user.platform_owner?

        user.admin? && user.customer_id == @generation.customer_id
      end

      def module_enabled?
        FeatureModules::Module.enabled?(
          key: AiAssistant::Activities::Preflight::MODULE_KEY,
          customer_id: @generation.customer_id
        )
      end

      def provider_configured?
        AiAssistant::ProviderSettings.active_for(:generation).present?
      end

      def denied(code)
        Result.new(allowed: false, error_code: code)
      end
    end
  end
end
