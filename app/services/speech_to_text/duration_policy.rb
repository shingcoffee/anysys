# frozen_string_literal: true

module SpeechToText
  # Single source of truth for how long one dictation may be.
  #
  # The enqueue activity and DictateFieldComponent used to read and clamp
  # `max_duration_seconds` independently, with different rules — the component
  # ignored ABSOLUTE_MAX, so the browser could be told a limit the server would
  # then reject. Both now resolve the cap here, so the widget always advertises
  # exactly the cap the server enforces.
  module DurationPolicy
    MODULE_KEY            = "ai_assistant"
    DEFAULT_MAX_DURATION  = 60
    ABSOLUTE_MAX_DURATION = 120

    class << self
      # Effective cap in seconds for one tenant. Falls back to the default on a
      # missing/garbage tenant value and never exceeds ABSOLUTE_MAX_DURATION.
      def max_duration_seconds(customer_id:)
        clamp(configured_max(customer_id))
      end

      def clamp(raw)
        value = Integer(raw, exception: false)
        value = DEFAULT_MAX_DURATION if value.nil? || value <= 0
        [ value, ABSOLUTE_MAX_DURATION ].min
      end

      def assignment(customer_id)
        return nil if customer_id.blank?

        FeatureModules::CustomerAssignment
          .joins(:feature_module)
          .find_by(customer_id: customer_id, feature_modules: { key: MODULE_KEY })
      end

      private

      # A tenant with unreadable configuration must still be able to dictate at
      # the default cap, so this stays fail-safe — but the cause is logged
      # rather than swallowed, since reaching here means the tenant's configured
      # limit is silently not being honoured.
      def configured_max(customer_id)
        assignment(customer_id)&.configuration_json&.dig("max_duration_seconds")
      rescue StandardError => e
        Rails.logger.error(
          "[SpeechToText::DurationPolicy] falling back to the default duration cap " \
          "for customer=#{customer_id}: #{e.class}: #{e.message}"
        )
        nil
      end
    end
  end
end
