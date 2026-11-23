# frozen_string_literal: true

require "benchmark"

module Captcha
  module Activities
    # Vendor-agnostic captcha verification. Resolves the active provider from
    # Captcha::ProviderSettings.active, applies replay + score-threshold guards,
    # and dispatches to the provider. The fail-open vs fail-closed *decision*
    # is left to the caller (CaptchaProtectable), which knows the per-action
    # policy — this activity only classifies the outcome.
    class Verify
      # `fail_policy` carries the resolved platform fail policy ("open"/"closed",
      # nil when captcha is disabled) so the caller does not re-query the settings
      # row it already resolved here.
      Result = Struct.new(:outcome, :raw, :http_status, :score, :fail_policy, keyword_init: true) do
        HARD_BLOCK = %i[invalid replayed].freeze

        # Captcha verified — always let the request through.
        def passed? = outcome == :success

        # Definitively rejected (bad or reused token) — always block, regardless
        # of fail policy.
        def blocked_hard? = HARD_BLOCK.include?(outcome)

        # Captcha intentionally not configured — must never block a form under
        # any policy, else a platform misconfiguration DoSes every tenant.
        def disabled? = outcome == :disabled
      end

      # @param context [Captcha::VerificationContext]
      def self.call(context:)
        settings = Captcha::ProviderSettings.active
        return result(:disabled, settings: nil) if settings.nil?

        return result(:invalid, settings: settings) if context.blank_token?

        if Captcha::TokenReplay.consumed?(context.token_digest)
          return result(:replayed, settings: settings)
        end

        adapter_result = nil
        duration = Benchmark.realtime do
          adapter_result = settings.provider_class.verify(settings: settings, context: context)
        end

        outcome = apply_score_threshold(adapter_result, settings)
        instrument(outcome, adapter_result, duration, provider: settings.provider)
        if outcome == :success && !Captcha::TokenReplay.consume!(context.token_digest)
          outcome = :replayed
        end
        result(outcome, settings: settings, raw: adapter_result[:raw],
               http_status: adapter_result[:http_status], score: adapter_result[:score])
      end

      # Score-based providers (reCAPTCHA v3 etc.): a passing token below the
      # configured threshold is treated as invalid. Binary providers (no score,
      # or no threshold set) are unaffected. A configured threshold with no
      # score to compare against cannot be honoured, so it fails closed rather
      # than silently letting the request bypass the gate.
      def self.apply_score_threshold(adapter_result, settings)
        outcome = adapter_result[:outcome]
        return outcome unless outcome == :success && settings.score_based?

        threshold = settings.score_threshold
        return outcome if threshold.nil?

        score = adapter_result[:score]
        return :invalid if score.nil?

        score.to_f >= threshold.to_f ? :success : :invalid
      end

      def self.instrument(outcome, adapter_result, duration, provider:)
        ActiveSupport::Notifications.instrument(
          "captcha.verify",
          duration:    duration,
          outcome:     outcome,
          http_status: adapter_result[:http_status],
          score:       adapter_result[:score],
          provider:    provider
        )
      end

      def self.result(outcome, settings:, raw: nil, http_status: nil, score: nil)
        Result.new(outcome: outcome, raw: raw, http_status: http_status, score: score,
                   fail_policy: settings&.fail_policy)
      end
    end
  end
end
