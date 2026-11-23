# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class FormatValueGenerator < BaseGenerator
          FORMAT_TYPES = FlowchartRuntime::Formatter::FORMAT_TYPES
          PHONE_STYLES = FlowchartRuntime::Formatter::PHONE_STYLES
          DATE_STYLES = FlowchartRuntime::Formatter::DATE_STYLES
          NUMERIC_TYPES = FlowchartRuntime::Formatter::NUMERIC_TYPES

          generator_metadata do
            description "Formats a value for templates, documents, and messages in the run locale: number, " \
                        "currency, percentage, delimited, human_size, human_number, phone (phonelib), date, " \
                        "or datetime (I18n.l). Reads sourceVariable. Writes resultVar as a string. Honors ctx[:locale] " \
                        "when locale is blank. Use date_time_calc for date math and math_operation for decimal " \
                        "arithmetic. Fails with format_value.failed on an invalid timezone; writes fallbackValue " \
                        "when the source is blank or cannot be formatted."
            category :data_operations
            version "1.1.0"
            presentation icon: "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z",
                          color: "cyan", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "amount",
              description: "Context path of the value to format (e.g. params.amount, a Time, or a phone string)."
            enum :formatType, FORMAT_TYPES, default: "number",
              description: "How to present the value. number/currency/percentage/delimited/human_* use NumberHelper; " \
                           "phone uses phonelib; date and datetime use I18n.l or iso8601/custom strftime."
            literal :locale, default: "", placeholder: true,
              description: "I18n locale for number and date formats (e.g. en or zh-CN). Blank uses ctx[:locale] or I18n.locale."
            integer :precision, min: 0, max: 10, default: 2, visible: { formatType: NUMERIC_TYPES - %w[delimited] },
              description: "Digits after the decimal, or significant digits for human_size and human_number (0-10). Default 2."
            literal :currencyUnit, default: "", placeholder: true, visible: { formatType: "currency" },
              description: "Currency symbol or code passed to number_to_currency (e.g. $ or CNY). Blank uses the locale default."
            literal :delimiter, default: "", placeholder: true, group: :advanced, visible: { formatType: NUMERIC_TYPES },
              description: "Thousands delimiter (e.g. , or .). Blank uses the locale number.format.delimiter."
            literal :separator, default: "", placeholder: true, group: :advanced, visible: { formatType: NUMERIC_TYPES },
              description: "Decimal separator (e.g. . or ,). Blank uses the locale number.format.separator."
            flag :stripInsignificantZeros, default: false, visible: { formatType: NUMERIC_TYPES },
              description: "Drop trailing zeros after the decimal (1.50 becomes 1.5)."
            literal :phoneCountry, default: "", placeholder: true, visible: { formatType: "phone" },
              description: "ISO alpha-2 country used to parse a national number (e.g. CN or US). Blank requires an international number."
            enum :phoneStyle, PHONE_STYLES, default: "international", visible: { formatType: "phone" },
              description: "How to print a valid phone: international (+86 138 ...), national, or e164 (+86138...)."
            enum :dateStyle, DATE_STYLES, default: "default", visible: { formatType: %w[date datetime] },
              description: "Date format: default, short, and long use I18n.l; iso8601 is ISO; custom uses customFormat."
            literal :customFormat, placeholder: true, example: "%Y-%m-%d", visible: { dateStyle: "custom" },
              description: "strftime pattern when dateStyle is custom. Example: %Y-%m-%d %H:%M."
            literal :timezone, default: "", placeholder: true, visible: { formatType: "datetime" },
              description: "IANA timezone for datetime (e.g. Asia/Shanghai). Blank uses Time.zone."
            literal :fallbackValue, default: "", placeholder: true,
              description: "Text written when the source is nil or cannot be formatted. Example: — or n/a. Blank writes an empty string."
            output :resultVar, default: "formatted",
              description: "Context variable that receives the formatted display string."
            requires :customFormat, when: { dateStyle: "custom" }

            validate do |_cfg, errors|
              validate_timezone(errors)
              validate_phone_country(errors)
            end
          end

          def generate_body
            body(
              attempt('"format_value.failed"', FlowchartRuntime::Formatter::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Formatter.apply(#{apply_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def apply_args
            type = value(:formatType).to_s
            args = [read(:sourceVariable), "ctx: ctx", "format_type: #{read(:formatType)}"]
            append_kw(args, "locale", read(:locale), omit: '""')
            if NUMERIC_TYPES.include?(type)
              append_kw(args, "precision", read(:precision), omit: "2") unless type == "delimited"
              append_kw(args, "currency_unit", read(:currencyUnit), omit: '""') if type == "currency"
              append_kw(args, "delimiter", read(:delimiter), omit: '""')
              append_kw(args, "separator", read(:separator), omit: '""')
              append_kw(args, "strip_insignificant_zeros", read(:stripInsignificantZeros), omit: "false")
            elsif type == "phone"
              append_kw(args, "phone_country", read(:phoneCountry), omit: '""')
              append_kw(args, "phone_style", read(:phoneStyle), omit: '"international"')
            elsif %w[date datetime].include?(type)
              append_kw(args, "date_style", read(:dateStyle), omit: '"default"')
              if value(:dateStyle).to_s == "custom"
                custom = value(:customFormat).to_s
                append_kw(args, "custom_format", custom.empty? ? '""' : read(:customFormat), omit: '""')
              end
              append_kw(args, "timezone", read(:timezone), omit: '""') if type == "datetime"
            end
            append_kw(args, "fallback_value", read(:fallbackValue), omit: '""')
            args.join(", ")
          end

          def append_kw(args, name, source, omit:)
            args << "#{name}: #{source}" unless source == omit
          end

          def validate_timezone(errors)
            zone = value(:timezone).to_s.strip
            return if zone.empty?
            return if Time.find_zone(zone) || ActiveSupport::TimeZone[zone]

            errors.add(:timezone, :invalid_timezone)
          end

          def validate_phone_country(errors)
            country = value(:phoneCountry).to_s.strip
            return if country.empty? || FlowchartRuntime::ValueValidator.valid_phone_country?(country)

            errors.add(:phoneCountry, :invalid_phone_country)
          end
        end
      end
    end
  end
end
