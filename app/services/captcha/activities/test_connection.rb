# frozen_string_literal: true

module Captcha
  module Activities
    # Platform-owner health probe for a provider's credentials, run off the
    # request path (the "Test connection" button). Sends a sentinel token
    # straight to the vendor — bypassing the verify activity so the probe never
    # writes a replay digest — and classifies the response:
    #
    #   reached vendor, token rejected (:invalid/:success) -> credentials OK
    #   4xx credential/request error (:configuration_error) -> bad credentials
    #   5xx / timeout / network (:unreachable)              -> vendor unreachable
    #
    # Writes the result to last_health_check_* so the settings card reflects it.
    class TestConnection
      PROBE_TOKEN = "captcha-connection-probe"

      Result = Struct.new(:status, keyword_init: true) do
        def ok? = status == "ok"
      end

      def self.call(settings:)
        return persist(settings, "configuration_error", "not configured") unless settings.configured?

        context = Captcha::VerificationContext.new(verify_param: PROBE_TOKEN, action: :connection_test)
        adapter = settings.provider_class.verify(settings: settings, context: context)

        status = case adapter[:outcome]
        when :success, :invalid   then "ok"
        when :configuration_error then "configuration_error"
        else                           "unreachable"
        end
        persist(settings, status, diagnostic_message(adapter[:raw]))
      rescue Captcha::Errors::TransportError => e
        persist(settings, "unreachable", e.message)
      end

      # Vendor diagnostic message — stored for debugging only, never rendered to
      # the user (the UI shows the localized status key instead).
      def self.diagnostic_message(raw)
        return nil unless raw.is_a?(Hash)

        (raw["Message"] || raw["message"] || Array(raw["error-codes"]).join(", ")).to_s.presence
      end

      def self.persist(settings, status, message)
        settings.update_columns(
          last_health_check_at:      Time.current,
          last_health_check_status:  status,
          last_health_check_message: message
        )
        Result.new(status: status)
      end
    end
  end
end
