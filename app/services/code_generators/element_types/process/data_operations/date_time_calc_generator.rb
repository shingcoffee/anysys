# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class DateTimeCalcGenerator < BaseGenerator
          OPERATIONS = FlowchartRuntime::Dates::OPERATIONS
          UNITS = FlowchartRuntime::Dates::UNITS
          DST_POLICIES = FlowchartRuntime::Dates::DST_POLICIES
          DST_BEHAVIORS = FlowchartRuntime::Dates::DST_BEHAVIORS
          OUTPUT_KEYWORDS = FlowchartRuntime::Dates::OUTPUT_FORMATS
          SHIFT_OPS = %w[add subtract].freeze
          RANGE_OPS = %w[difference compare].freeze
          ZONE_OPS = %w[now add subtract difference start_of end_of age compare format parse].freeze
          OUTPUT_OPS = %w[now add subtract start_of end_of parse convert_timezone].freeze

          generator_metadata do
            description "Calculates dates and times in the run time zone: current time, add or subtract " \
                        "a duration (including business days), start or end of a period, difference in a unit, " \
                        "compare two instants, age in whole years from a birth date, parse, format, or convert " \
                        "a timezone. Reads sourceVariable (and endVariable for difference, compare, and age-at). " \
                        "Writes resultVar. Use format_value for locale-aware display and next_occurrence for " \
                        "recurring due dates. Fails with date_time_calc.failed when the source cannot be parsed " \
                        "or a timezone is invalid."
            category :data_operations
            version "1.1.0"
            presentation icon: "M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
                         color: "amber", single_use: false, privileged: false
          end

          config_schema do
            enum :operation, OPERATIONS, default: "now",
              description: "Calculation to run. now is Time.current (no source). add/subtract shift source by amount " \
                           "and unit. difference is end minus source in unit. start_of/end_of snap to the period. " \
                           "age is whole years from source to now or endVariable. compare is -1/0/1. " \
                           "format uses formatString. parse reads a string. convert_timezone maps clocks."
            output :resultVar, default: "datetime",
              description: "Context variable that receives the Time, integer (difference, age, compare), or formatted string."
            input :sourceVariable, example: "start_date",
              visible: { operation: %w[add subtract difference start_of end_of age compare format parse convert_timezone] },
              description: "Context path of the source time (e.g. params.starts_on). Unused for now. " \
                           "Accepts a Time, Date, or parseable string."
            input :endVariable, example: "end_date", visible: { operation: %w[difference compare age] },
              description: "Context path of the second instant. Required for difference and compare; " \
                           "optional for age as the as-of date instead of now (e.g. params.ends_on)."
            integer :amount, min: 0, max: 10_000, default: 1, visible: { operation: SHIFT_OPS },
              description: "How many units to add or subtract (0-10000). Example: 14 with unit days is two weeks."
            enum :unit, UNITS, default: "days",
              visible: { operation: %w[add subtract difference start_of end_of] },
              description: "Duration unit for add, subtract, and difference, and the period for start_of/end_of " \
                           "(days is beginning/end of day). seconds, minutes, hours, days, weeks, months, years."
            literal :formatString, default: "%Y-%m-%d", placeholder: true, visible: { operation: "format" },
              description: "strftime pattern used by format. Example: %Y-%m-%d %H:%M. Use format_value for locale display."
            literal :inputFormat, default: "", placeholder: true, visible: { operation: "parse" },
              description: "strptime pattern for parse, or blank/iso to use Time.zone.parse. Example: %d/%m/%Y."
            literal :outputFormat, default: "", placeholder: true, visible: { operation: OUTPUT_OPS },
              description: "How to write a Time result: blank keeps the Time; iso8601, rfc3339, unix, unix_ms, " \
                           "or a strftime pattern such as %Y-%m-%d."
            flag :businessDays, default: false, visible: { operation: SHIFT_OPS },
              description: "When adding or subtracting days or weeks, skip Saturdays and Sundays (weeks counts five days each)."
            flag :timezoneAware, default: false, visible: { operation: ZONE_OPS },
              description: "Interpret times in Time.zone (or timezone when set). Off leaves a Time object in its own zone."
            literal :timezone, default: "", placeholder: true, visible: { timezoneAware: true },
              description: "IANA timezone such as Asia/Shanghai. Blank with timezoneAware uses Time.zone."
            enum :dstPolicy, DST_POLICIES, default: "preserve_wall", visible: { operation: SHIFT_OPS },
              description: "How add/subtract crosses DST. preserve_wall keeps clock time (Rails default); " \
                           "preserve_utc shifts the UTC instant then converts back."
            literal :sourceTimezone, default: "UTC", placeholder: true, visible: { operation: "convert_timezone" },
              description: "IANA zone of the source clock for convert_timezone. Example: UTC or America/New_York."
            literal :targetTimezone, default: "UTC", placeholder: true, visible: { operation: "convert_timezone" },
              description: "IANA zone to convert into for convert_timezone. Example: Asia/Shanghai. Default UTC."
            flag :preserveLocalTime, default: false, visible: { operation: "convert_timezone" },
              description: "For convert_timezone, keep wall-clock fields and change the zone instead of converting the instant."
            enum :dstBehavior, DST_BEHAVIORS, default: "prefer_later", visible: { operation: "convert_timezone" },
              description: "When preserveLocalTime hits an ambiguous DST time: raise_on_ambiguous fails the step; " \
                           "prefer_earlier or prefer_later picks that offset."
            requires :sourceVariable, when: { operation: %w[add subtract difference start_of end_of age compare format parse convert_timezone] }
            requires :endVariable, when: { operation: RANGE_OPS }
            requires :amount, when: { operation: SHIFT_OPS }
            requires :unit, when: { operation: SHIFT_OPS + %w[difference start_of end_of] }
            requires :formatString, when: { operation: "format" }
            requires :targetTimezone, when: { operation: "convert_timezone" }

            validate do |_cfg, errors|
              validate_output_format(errors)
              validate_timezone_name(errors, :timezone)
              validate_timezone_name(errors, :sourceTimezone)
              validate_timezone_name(errors, :targetTimezone)
            end
          end

          def generate_body
            body(
              attempt('"date_time_calc.failed"', FlowchartRuntime::Dates::Error) do
                [
                  assign(:resultVar, dates_call),
                  "true"
                ]
              end
            )
          end

          private

          def dates_call
            op = value(:operation).to_s
            args = [source_expr, "operation: #{read(:operation)}"]
            append_kw(args, "end_value", end_expr, omit: "nil") if %w[difference compare age].include?(op)
            if SHIFT_OPS.include?(op)
              append_kw(args, "amount", read(:amount), omit: "1")
              append_kw(args, "unit", read(:unit), omit: '"days"')
              append_kw(args, "business_days", read(:businessDays), omit: "false")
              append_kw(args, "dst_policy", read(:dstPolicy), omit: '"preserve_wall"')
            elsif %w[difference start_of end_of].include?(op)
              append_kw(args, "unit", read(:unit), omit: '"days"')
            end
            append_kw(args, "format_string", read(:formatString), omit: '"%Y-%m-%d"') if op == "format"
            append_kw(args, "input_format", blank_to_nil(read(:inputFormat)), omit: "nil") if op == "parse"
            append_kw(args, "output_format", blank_to_nil(read(:outputFormat)), omit: "nil") if OUTPUT_OPS.include?(op)
            if ZONE_OPS.include?(op)
              append_kw(args, "timezone_aware", read(:timezoneAware), omit: "false")
              append_kw(args, "timezone", blank_to_nil(read(:timezone)), omit: "nil")
            end
            if op == "convert_timezone"
              append_kw(args, "source_timezone", read(:sourceTimezone), omit: '"UTC"')
              append_kw(args, "target_timezone", blank_to_nil(read(:targetTimezone)), omit: ["nil", '"UTC"'])
              append_kw(args, "preserve_local_time", read(:preserveLocalTime), omit: "false")
              append_kw(args, "dst_behavior", read(:dstBehavior), omit: '"prefer_later"')
            end
            "FlowchartRuntime::Dates.apply(#{args.join(", ")})"
          end

          def append_kw(args, name, source, omit:)
            args << "#{name}: #{source}" unless Array(omit).include?(source)
          end

          def blank_to_nil(source)
            source == '""' ? "nil" : source
          end

          def source_expr
            value(:sourceVariable).present? ? read(:sourceVariable) : "nil"
          end

          def end_expr
            value(:endVariable).present? ? read(:endVariable) : "nil"
          end

          def validate_output_format(errors)
            fmt = value(:outputFormat).to_s
            return if fmt.blank?
            return if OUTPUT_KEYWORDS.include?(fmt) || fmt.include?("%")

            errors.add(:outputFormat, :invalid_format)
          end

          def validate_timezone_name(errors, field)
            zone = value(field).to_s.strip
            return if zone.empty?
            return if Time.find_zone(zone) || ActiveSupport::TimeZone[zone]

            errors.add(field, :invalid_timezone)
          end
        end
      end
    end
  end
end
