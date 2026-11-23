# frozen_string_literal: true

module Emails
  module SendActivities
    module RecurrencePresets
      PRESETS = {
        "none" => nil,
        "daily" => "FREQ=DAILY;INTERVAL=1",
        "weekly" => "FREQ=WEEKLY;INTERVAL=1",
        "monthly" => "FREQ=MONTHLY;INTERVAL=1"
      }.freeze

      def self.rrule_for(preset) = PRESETS.fetch(preset.to_s) { raise KeyError, preset }

      def self.preset_for(rrule)
        return "none" if rrule.blank?

        PRESETS.key(rrule).presence || "none"
      end

      def self.select_options
        PRESETS.keys.map do |key|
          [I18n.t("admin_modules.emails.send_activities.form.recurrence_presets.#{key}"), key]
        end
      end
    end
  end
end
