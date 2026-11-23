# frozen_string_literal: true

require_relative "../providers"

module Captcha
  module Providers
    # Google reCAPTCHA v3 — invisible, score-based verification.
    #
    # The public Site Key is stored in `access_key_id`; the private Secret Key
    # is stored in `access_key_secret`. reCAPTCHA v3 returns a 0.0–1.0 score
    # which is compared against `ProviderSettings#score_threshold` (default 0.5).
    #
    # Outcomes:
    #   :success              -> HTTP 200 + success == true + score >= threshold
    #   :invalid              -> success == true + score < threshold,
    #                            or success == false with user-side error codes
    #   :configuration_error  -> credential/request error (bad secret, etc.)
    #   :unreachable          -> HTTP 5xx, timeout, network error
    class GoogleRecaptchaV3 < Base
      SITEVERIFY_URL = "https://www.google.com/recaptcha/api/siteverify"
      SDK_URL = "https://www.google.com/recaptcha/api.js"

      CONFIG_ERROR_CODES = %w[
        missing-input-secret invalid-input-secret bad-request
      ].freeze

      class << self
        def key                  = "google_recaptcha_v3"
        def default_display_name = "Google reCAPTCHA v3"

        def config_fields = []

        def score_based?
          true
        end

        def invisible?
          true
        end

        def configured?(settings)
          settings.access_key_id.present? && settings.access_key_secret.present?
        end

        def widget(settings)
          {
            stimulus_controller: "captcha-google-recaptcha-v3",
            data: {
              "captcha-google-recaptcha-v3-site-key-value" => settings.access_key_id.to_s,
              "captcha-google-recaptcha-v3-sdk-url-value"  => "#{SDK_URL}?render=#{settings.access_key_id}"
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
            score:       json.is_a?(Hash) ? json["score"] : nil,
            hostname:    json.is_a?(Hash) ? json["hostname"] : nil
          }
        end
      end

      private

      def map_outcome(res, json, context)
        code = res.code.to_i
        return :unreachable if code >= 500

        if json.is_a?(Hash) && json.key?("success")
          if json["success"] == true
            return :invalid unless context.matches_vendor_context?(json, provider: self.class.key)
            score = json["score"]
            return :invalid unless score.is_a?(Numeric) && score.finite? && score.between?(0, 1)
            threshold = settings.score_threshold || 0.5
            return score >= threshold ? :success : :invalid
          end

          codes = Array(json["error-codes"])
          return :configuration_error if (codes & CONFIG_ERROR_CODES).any?

          return :invalid
        end

        code >= 400 ? :configuration_error : :unreachable
      end
    end
  end
end
