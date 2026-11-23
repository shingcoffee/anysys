# frozen_string_literal: true

module AiAssistant
  module Activities
    # Platform-owner health probe for a provider's credentials. The "Test
    # connection" button runs it live on the request (no queue) so the owner
    # sees the outcome immediately; TestConnectionJob also runs it after a
    # Cursor save to refresh the model list. Delegates to the adapter's
    # #health_check — Whisper-family vendors send a silent WAV; Cursor lists
    # models — and classifies the response:
    #
    #   reached vendor, transcribed or empty (:success/:empty) -> credentials OK
    #   4xx credential/request error (:configuration_error)    -> bad credentials
    #   5xx / timeout / network (:unreachable)                 -> vendor unreachable
    #
    # Writes the result to last_health_check_* so the settings card reflects it,
    # and returns the vendor's own error text as Result#message so the caller
    # can report it verbatim. Cursor returns listed models on the result; this
    # activity writes them with update_columns so a full save! cannot clobber a
    # concurrent edit.
    class TestConnection
      MESSAGE_LIMIT = 500

      Result = Struct.new(:status, :message, keyword_init: true) do
        def ok? = status == "ok"
      end

      def self.call(settings:)
        unless settings.configured?
          return persist(settings, "configuration_error",
                         I18n.t("ai_assistant.platform_settings.errors.unconfigured_assignee"))
        end

        adapter = settings.provider_class.new(settings: settings)
        result = adapter.health_check

        status = case result[:outcome]
        when :success, :empty     then "ok"
        when :configuration_error then "configuration_error"
        else                           "unreachable"
        end
        message = diagnostic_message(result) unless status == "ok"
        persist(settings, status, message, models: result[:models])
      rescue StandardError => e
        Rails.logger.warn("[AiAssistant::TestConnection] #{settings.provider}: #{e.class}: #{e.message}")
        persist(settings, "unreachable", e.message.presence || e.class.name)
      end

      def self.diagnostic_message(result)
        vendor_message(result[:raw]) || http_status_message(result[:http_status])
      end

      def self.vendor_message(raw)
        return nil unless raw.is_a?(Hash)

        error = raw["error"] || raw[:error]
        error = error["message"] || error[:message] if error.is_a?(Hash)
        (error || raw["message"] || raw[:message] || raw["Message"]).to_s.presence
      end

      def self.http_status_message(status)
        return nil if status.blank?

        I18n.t("ai_assistant.platform_settings.test.http_status", status: status)
      end

      def self.persist(settings, status, message, models: nil)
        message = message.to_s.squish.truncate(MESSAGE_LIMIT).presence
        attrs = {
          last_health_check_at:      Time.current,
          last_health_check_status:  status,
          last_health_check_message: message
        }
        if models.is_a?(Array)
          settings.reload
          settings.write_config(generation_models: models)
          attrs[:config] = settings.config
        end
        settings.update_columns(attrs)
        Result.new(status: status, message: message)
      end
    end
  end
end
