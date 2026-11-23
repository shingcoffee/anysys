# frozen_string_literal: true

# Captcha::Providers (registry) is referenced by `register!` at class-body load
# time. Force-load it so this file is safe to require in isolation.
require_relative "../providers"

module Captcha
  module Providers
    # Cloudflare Turnstile (siteverify). A privacy-first, modern reCAPTCHA
    # alternative. Binary pass/fail (no score); Cloudflare enforces single-use
    # server-side (`timeout-or-duplicate`), which we additionally back-stop with
    # the app-layer replay ledger.
    #
    # The two shared credential columns map onto Turnstile's key pair:
    #   access_key_id     -> Site Key   (public, embedded in the widget)
    #   access_key_secret -> Secret Key (private, used by siteverify)
    #
    # Outcomes:
    #   :success              -> HTTP 200 + success == true
    #   :invalid              -> bad/expired/duplicate token
    #   :configuration_error  -> credential/request error (bad secret, etc.)
    #   :unreachable          -> HTTP 5xx, timeout, network error
    class Turnstile < Base
      SITEVERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
      SDK_URL        = "https://challenges.cloudflare.com/turnstile/v0/api.js"

      # Error codes that indicate OUR misconfiguration (not an attacker's bad
      # token) — these must not fail-open as if the token were merely invalid.
      CONFIG_ERROR_CODES = %w[
        missing-input-secret invalid-input-secret bad-request internal-error
      ].freeze

      class << self
        def key                  = "turnstile"
        def default_display_name = "Cloudflare Turnstile"

        # Site Key + Secret Key live in the shared credential columns, so no
        # extra JSON config fields are required.
        def config_fields = []

        def configured?(settings)
          settings.access_key_id.present? && settings.access_key_secret.present?
        end

        def widget(settings)
          {
            stimulus_controller: "captcha-turnstile",
            sdk_url:             SDK_URL,
            data: {
              "captcha-turnstile-site-key-value" => settings.access_key_id.to_s,
              "captcha-turnstile-sdk-url-value"  => SDK_URL
            }
          }
        end
      end

      register!

      def verify(context:)
        with_transport_rescue do
          params = {
            "secret"   => settings.access_key_secret.to_s,
            "response" => context.verify_param
          }
          params["remoteip"] = context.remoteip if context.remoteip.present?

          res, json = http_post_form(SITEVERIFY_URL, params)
          {
            outcome:     map_outcome(res, json, context),
            http_status: res.code.to_i,
            raw:         json,
            score:       nil,
            hostname:    json["hostname"]
          }
        end
      end

      private

      def map_outcome(res, json, context)
        code = res.code.to_i
        return :unreachable if code >= 500

        # Cloudflare puts the real signal in the body (success + error-codes) and
        # normally answers 200 even for a bad token/secret. Trust the body when
        # present — regardless of status — so an attacker-influenced token that
        # somehow rides a 4xx is still classified :invalid (a hard block), never
        # a fail-open :configuration_error.
        if json.is_a?(Hash) && json.key?("success")
          if json["success"] == true
            return context.matches_vendor_context?(json, provider: self.class.key) ? :success : :invalid
          end

          codes = Array(json["error-codes"])
          return :configuration_error if (codes & CONFIG_ERROR_CODES).any?

          return :invalid
        end

        # No usable body: a 4xx is a request/credential problem; otherwise treat
        # as a transport-level failure.
        code >= 400 ? :configuration_error : :unreachable
      end
    end
  end
end
