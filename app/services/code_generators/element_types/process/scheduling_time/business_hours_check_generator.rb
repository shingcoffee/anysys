# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module SchedulingTime
        class BusinessHoursCheckGenerator < BaseGenerator
          DAYS = FlowchartRuntime::BusinessHours::DAYS
          RESULT_MODES = %w[bool next_open minutes_until_open add_business_minutes].freeze

          generator_metadata do
            description "Evaluates a weekly schedule in an IANA timezone, with optional holiday dates. Use deadline_check for an SLA instant. schedule maps monday..sunday to 'HH:MM-HH:MM'; comma-separate two windows for a lunch break ('09:00-12:00,13:00-17:00'). Reads timeVariable or Time.current. resultMode 'bool' writes open? to resultVar; 'next_open' writes the next opening Time; 'minutes_until_open' writes minutes until then; 'add_business_minutes' adds businessMinutes of open time. Omit a weekday to close it. Fails with business_hours_check.failed on a bad timezone, holiday, or when added minutes exceed the horizon."
            category :scheduling_time
            version "2.2.0"
            presentation icon: "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            mapping :schedule, key: :literal, value: :literal, required: true,
                    example: [{ "key" => "monday", "value" => "09:00-17:00" },
                              { "key" => "tuesday", "value" => "09:00-17:00" },
                              { "key" => "wednesday", "value" => "09:00-17:00" },
                              { "key" => "thursday", "value" => "09:00-17:00" },
                              { "key" => "friday", "value" => "09:00-17:00" }],
                    description: "Weekday (monday..sunday) to 'HH:MM-HH:MM'. Lunch break: '09:00-12:00,13:00-17:00'. Omit a day to close it."
            mapping :holidays, key: :literal, value: :literal, default: [],
                    description: "Closed dates as YYYY-MM-DD keys (value is a label). Example key '2026-12-25'."
            literal :timezone, default: "UTC", placeholder: true,
                    description: "IANA timezone used to evaluate the schedule, e.g. 'America/New_York'. Default 'UTC'."
            input :timeVariable,
                    description: "ctx path holding a Time or ISO8601 string. Blank uses Time.current."
            enum :resultMode, RESULT_MODES, default: "bool",
                    description: "'bool' writes open?. 'next_open' writes the next opening Time. 'minutes_until_open' writes minutes until then. 'add_business_minutes' adds businessMinutes."
            integer :businessMinutes, min: 0, max: 525_600, default: 0, visible: { resultMode: "add_business_minutes" },
                    description: "Open minutes to add to the start time when resultMode is add_business_minutes (0-525600)."
            output :resultVar, default: "hours_status",
                    description: "ctx variable that receives the check result. Default 'hours_status'."
            validate do |cfg, errors|
              validate_timezone(cfg, errors)
              validate_schedule_rows(cfg, errors)
              validate_holiday_rows(cfg, errors)
              errors.add(:schedule, :required) if Array(cfg["schedule"]).empty?
            end
          end

          def generate_body
            if value(:resultMode) == "add_business_minutes"
              return attempt('"business_hours_check.failed"', FlowchartRuntime::BusinessHours::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::BusinessHours.add_minutes(#{hours_args})"),
                  "true"
                ]
              end
            end

            attempt('"business_hours_check.failed"', FlowchartRuntime::BusinessHours::Error) do
              [
                "check = FlowchartRuntime::BusinessHours.open?(#{hours_args})",
                assign(:resultVar, selected_result),
                "true"
              ]
            end
          end

          private

          def hours_args
            [
              "schedule: #{read(:schedule)}",
              "at: #{at_source}",
              "timezone: #{read(:timezone)}",
              ("holidays: #{read(:holidays)}" if Array(value(:holidays)).any?),
              ("minutes: #{read(:businessMinutes)}" if value(:resultMode) == "add_business_minutes" && value(:businessMinutes) != 0)
            ].compact.join(", ")
          end

          def at_source
            value(:timeVariable).to_s.strip.present? ? "#{read(:timeVariable)} || Time.current" : "Time.current"
          end

          def selected_result
            case value(:resultMode)
            when "next_open"
              "check[:next_open_at]"
            when "minutes_until_open"
              "check[:minutes_until_open]"
            else
              "check[:open]"
            end
          end

          def validate_timezone(cfg, errors)
            tz = cfg["timezone"].to_s
            return if tz.empty?
            return if ActiveSupport::TimeZone[tz].present?

            TZInfo::Timezone.get(tz)
          rescue TZInfo::InvalidTimezoneIdentifier
            errors.add(:timezone, :invalid_timezone)
          end

          def validate_schedule_rows(cfg, errors)
            Array(cfg["schedule"]).each do |row|
              next unless row.is_a?(Hash)

              day = (row["key"] || row[:key]).to_s.downcase
              range = (row["value"] || row[:value]).to_s
              unless DAYS.include?(day) && FlowchartRuntime::BusinessHours.valid_windows?(range)
                errors.add(:schedule, :invalid_schedule)
              end
            end
          end

          def validate_holiday_rows(cfg, errors)
            Array(cfg["holidays"]).each do |row|
              next unless row.is_a?(Hash)

              date = (row["key"] || row[:key]).to_s
              Date.iso8601(date)
            rescue Date::Error
              errors.add(:holidays, :invalid_holidays)
            end
          end
        end
      end
    end
  end
end
