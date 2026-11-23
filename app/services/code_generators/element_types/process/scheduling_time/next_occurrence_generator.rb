# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module SchedulingTime
        class NextOccurrenceGenerator < BaseGenerator
          FREQUENCIES = FlowchartRuntime::Recurrence::FREQUENCIES
          MONTH_END_POLICIES = FlowchartRuntime::Recurrence::MONTH_END_POLICIES
          BUSINESS_ADJUSTS = FlowchartRuntime::Recurrence::BUSINESS_ADJUSTS
          RETURNS = FlowchartRuntime::Recurrence::RETURNS
          SIMPLE_FREQUENCIES = %w[daily weekly monthly yearly].freeze

          generator_metadata do
            description "Computes the next run, renewal, or due instant from a calendar or cron recurrence " \
                        "in a named timezone (blank uses Time.zone). Reads optional startVariable, fromVariable, " \
                        "and untilVariable. Writes resultVar as one Time or a list. Use date_time_calc to add " \
                        "a one-off duration. Fails with next_occurrence.invalid_anchor when a bound is unparseable " \
                        "and next_occurrence.no_occurrence when nothing falls after from."
            category :scheduling_time
            version "1.1.0"
            presentation icon: "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            enum :frequency, FREQUENCIES, default: "monthly",
              description: "How the series repeats: daily, weekly (weekdays), monthly and yearly (dayOfMonth), or cron."
            integer :interval, min: 1, max: 366, default: 1, visible: { frequency: SIMPLE_FREQUENCIES },
              description: "Repeat every N periods (1-366). Example: 2 with monthly is every other month. Unused for cron."
            input :startVariable, example: "series_start",
              description: "Context path of the series anchor (e.g. params.starts_on). Blank uses Time.current in timezone."
            input :fromVariable, example: "after_time",
              description: "Context path of the time occurrences must be strictly after. Blank uses Time.current."
            list :weekdays, item: :literal, default: [], visible: { frequency: "weekly" },
              description: "Weekdays as mon, tue, wed, thu, fri, sat, sun. Blank uses the start weekday. Example: mon and thu."
            integer :dayOfMonth, min: -1, max: 31, default: 0, visible: { frequency: %w[monthly yearly] },
              description: "Day of month: 0 uses the start day, -1 the last day, 1-31 a fixed day. Combined with monthEndPolicy."
            enum :monthEndPolicy, MONTH_END_POLICIES, default: "clamp", visible: { frequency: %w[monthly yearly] },
              description: "When the month is shorter than dayOfMonth: clamp uses the last day (28 Feb); skip omits that month."
            literal :cronExpression, placeholder: true, example: "0 9 * * *", visible: { frequency: "cron" },
              description: "Five- or six-field cron used when frequency is cron. Example: 0 9 * * * for 09:00 every day."
            literal :timeOfDay, default: "", placeholder: true, visible: { frequency: SIMPLE_FREQUENCIES },
              description: "HH:MM applied to calendar occurrences (e.g. 09:30). Blank keeps the start time of day."
            literal :timezone, default: "", placeholder: true,
              description: "IANA timezone for the series (e.g. Asia/Shanghai). Blank uses Time.zone."
            enum :businessDayAdjust, BUSINESS_ADJUSTS, default: "none",
              description: "Weekend handling: none keeps Saturday/Sunday; next_business_day and previous_business_day shift to a weekday."
            enum :returns, RETURNS, default: "first",
              description: "first writes the next instant; list writes up to count upcoming instants."
            integer :count, min: 1, max: 366, default: 5, visible: { returns: "list" },
              description: "How many occurrences to return when returns is list (1-366). Default 5."
            input :untilVariable, group: :advanced,
              description: "Context path of the exclusive end of the series. Occurrences after this time are omitted."
            output :resultVar, default: "next_occurrence",
              description: "Context variable that receives the next Time, or an array of Times when returns is list."
            requires :cronExpression, when: { frequency: "cron" }

            validate do |_cfg, errors|
              validate_timezone(errors)
              validate_cron(errors)
              validate_time_of_day(errors)
              validate_weekdays(errors)
            end
          end

          def generate_body
            attempt('"next_occurrence.failed"', FlowchartRuntime::Recurrence::Error) do
              [
                "result = FlowchartRuntime::Recurrence.next_occurrences(#{occurrence_args})",
                "if result[:error]",
                '  return FlowchartRuntime::Step.fail(ctx, :"next_occurrence.#{result[:error]}")',
                "end",
                assign(:resultVar, "result[:value]"),
                "true"
              ]
            end
          end

          private

          def occurrence_args
            frequency = value(:frequency).to_s
            calendar = SIMPLE_FREQUENCIES.include?(frequency)
            monthly = %w[monthly yearly].include?(frequency)
            [
              "frequency: #{read(:frequency)}",
              ("interval: #{read(:interval)}" if calendar && value(:interval) != 1),
              ("start_at: #{read(:startVariable)}" if value(:startVariable).to_s.strip.present?),
              ("from: #{read(:fromVariable)}" if value(:fromVariable).to_s.strip.present?),
              ("weekdays: #{read(:weekdays)}" if frequency == "weekly" && Array(value(:weekdays)).any?),
              ("day_of_month: #{read(:dayOfMonth)}" if monthly && value(:dayOfMonth) != 0),
              ("month_end_policy: #{read(:monthEndPolicy)}" if monthly && value(:monthEndPolicy).to_s != "clamp"),
              ("cron_expression: #{read(:cronExpression)}" if frequency == "cron"),
              ("time_of_day: #{read(:timeOfDay)}" if calendar && value(:timeOfDay).to_s.strip.present?),
              ("timezone: #{read(:timezone)}" if value(:timezone).to_s.strip.present?),
              ("business_day_adjust: #{read(:businessDayAdjust)}" unless value(:businessDayAdjust).to_s == "none"),
              ("returns: #{read(:returns)}" unless value(:returns).to_s == "first"),
              ("count: #{read(:count)}" if value(:returns).to_s == "list" && value(:count) != 5),
              ("until_at: #{read(:untilVariable)}" if value(:untilVariable).to_s.strip.present?)
            ].compact.join(", ")
          end

          def validate_timezone(errors)
            zone = value(:timezone).to_s
            return if zone.empty?
            return if Time.find_zone(zone) || ActiveSupport::TimeZone[zone]

            errors.add(:timezone, :invalid_timezone)
          end

          def validate_cron(errors)
            return unless value(:frequency).to_s == "cron"

            cron = value(:cronExpression).to_s
            return if cron.present? && FlowchartRuntime::Schedule.valid_cron?(cron)

            errors.add(:cronExpression, :invalid_cron) if cron.present?
          end

          def validate_time_of_day(errors)
            return if FlowchartRuntime::Recurrence.valid_time_of_day?(value(:timeOfDay))

            errors.add(:timeOfDay, :invalid_time_of_day)
          end

          def validate_weekdays(errors)
            Array(value(:weekdays)).each do |day|
              next if FlowchartRuntime::Recurrence.valid_weekday?(day)

              errors.add(:weekdays, :invalid_weekday)
              break
            end
          end
        end
      end
    end
  end
end
