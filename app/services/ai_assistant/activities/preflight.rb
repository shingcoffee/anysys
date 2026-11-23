# frozen_string_literal: true

module AiAssistant
  module Activities
    # Shared request-path preflight for the two enqueue activities
    # (EnqueueTranscription, SendMessage). Both used to re-implement the same
    # module-enabled check, the same fail-closed provider check, the same rate
    # limit and the same Result/fail_result shape.
    #
    # Including classes must provide:
    #   #contract_valid? — run their own Reform contract
    #   #contract_errors — full messages from that contract
    #   #customer, #user
    #   #rate_scope      — a short string distinguishing the limiter bucket
    #   ::Result         — a Preflight::Result subclass (add a domain alias for
    #                      #record, e.g. `alias_method :clip, :record`)
    module Preflight
      MODULE_KEY = "ai_assistant"

      # One shape for both activities. `record` is whatever row the activity
      # created; each activity aliases it to a domain name for its callers.
      Result = Struct.new(:success?, :record, :http_status, :errors, :error_code, keyword_init: true)

      # @return [Preflight::Result, nil] the failure to return, or nil to proceed.
      def preflight_failure
        return fail_result(422, contract_errors) unless contract_valid?

        activity_guard ||
          disabled_failure ||
          unconfigured_failure ||
          rate_limited_failure
      end

      # Hook for guards that must run right after the contract and before the
      # module/provider/rate checks. Overridden by EnqueueTranscription.
      def activity_guard
        nil
      end

      def success_result(record, http_status: 202)
        self.class::Result.new(success?: true, record: record, http_status: http_status, errors: [])
      end

      def generation_handoff_result(generation:, record:)
        handoff = AiAssistant::Assistant::GenerationHandoff.call(generation: generation)
        return success_result(record) if handoff.success?

        fail_result(
          503,
          [ I18n.t("ai_assistant.assistant.reply_failed") ],
          error_code: handoff.failure_code
        )
      end

      def fail_result(status, errors, error_code: nil)
        self.class::Result.new(
          success?: false, record: nil, http_status: status,
          errors: Array(errors), error_code: error_code
        )
      end

      private

      def disabled_failure
        return nil if FeatureModules::Module.enabled?(key: MODULE_KEY, customer_id: customer.id)

        fail_result(403, [ I18n.t("ai_assistant.errors.module_disabled") ])
      end

      def provider_job
        :transcribe
      end

      def unconfigured_failure
        return nil if AiAssistant::ProviderSettings.active_for(provider_job)

        fail_result(403, [ I18n.t("ai_assistant.errors.unconfigured") ])
      end

      # Reuses the app's ONE shared-store limiter rather than a second copy.
      # Rails.cache#increment returns nil for a missing key on memory_store,
      # solid_cache and null_store and does NOT create it, so an
      # `increment(...).to_i > limit` check could never fire in any environment.
      # Authentication::Throttle seeds the key on first use and falls back to a
      # real store in test, so every window is both enforced and exercisable.
      #
      # Every attempt consumes all windows; report the tightest breached one.
      def rate_limited_failure
        # Consume each window atomically, including rejected attempts. A read
        # followed by a write lets concurrent paid requests share one slot.
        breached = nil
        AiAssistant::Limits::WINDOWS.each do |window|
          exceeded = throttle_for(window).hit!
          breached ||= window if exceeded
        end
        if breached
          return fail_result(429, [ I18n.t("#{rate_limited_scope}.#{breached.message_key}") ],
                             error_code: breached.name)
        end

        nil
      end

      # I18n scope holding a key per Limits::Window#message_key. Overridden by
      # including activities that report under their own module's namespace.
      def rate_limited_scope
        "ai_assistant.errors"
      end

      def throttle_for(window)
        Authentication::Throttle.new(
          key: rate_key(window),
          limit: window.limit,
          period: window.period
        )
      end

      # Bucketing the key by window start makes each window a fixed slice
      # rather than a sliding one, which is what keeps the counter cheap.
      def rate_key(window)
        bucket = (Time.current.utc.to_i / window.period.to_i) * window.period.to_i
        "ai_assistant:#{rate_scope}:#{window.name}:#{customer.id}:#{user.id}:#{bucket}"
      end
    end
  end
end
