# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class ValidateValueGenerator < BaseGenerator
          RULES = FlowchartRuntime::ValueValidator::RULES
          IP_VERSIONS = FlowchartRuntime::ValueValidator::IP_VERSIONS
          FIELD_FORMAT = /\A[a-z_][a-zA-Z0-9_]*\z/
          ON_INVALID = %w[fail flag].freeze

          generator_metadata do
            description "Validates one value against a business format and optionally writes a normalised " \
                        "copy: email, phone (including CN mobile), url, uuid, regex, length, numeric range, " \
                        "in_list, luhn, iban, Chinese resident ID, postal code, IP, date, date_range, or required. " \
                        "Reads sourceVariable. Writes resultVar (boolean) and normalizedVar. On fail (default) " \
                        "the submitter sees message next to errorField. Use regex_extract to pull a capture and " \
                        "format_value to display. Fails with validate_value.<rule> unless onInvalid is flag."
            category :validation
            version "1.1.0"
            presentation icon: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
                          color: "red", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "params.email",
              description: "Context path of the value to check (e.g. params.email)."
            enum :rule, RULES, default: "email",
              description: "Check to apply. required rejects blank. cn_mobile is a mainland China mobile number. " \
                           "date_range uses minDate/maxDate (ISO or today/tomorrow). phone uses phonelib."
            literal :phoneCountry, default: "", placeholder: true, visible: { rule: "phone" },
              description: "ISO alpha-2 country for national numbers (e.g. CN or US). Blank requires + or 00 international form."
            literal :pattern, placeholder: true, example: "\\A.+\\z", max_length: 4096, visible: { rule: "regex" },
              description: "Ruby regular expression the whole value must match. Example: \\A\\d{6}\\z for a 6-digit code."
            integer :minLength, min: 0, max: 10_000, default: 1, visible: { rule: "length" },
              description: "Shortest accepted string length (0-10000). Example: 8 for a password."
            integer :maxLength, min: 0, max: 10_000, default: 255, visible: { rule: "length" },
              description: "Longest accepted string length (0-10000). Must be >= minLength. Default 255."
            decimal :minValue, example: 0, visible: { rule: "range" },
              description: "Lowest accepted number. Leave blank for an open lower bound. Example: 0."
            decimal :maxValue, example: 100, visible: { rule: "range" },
              description: "Highest accepted number. Leave blank for an open upper bound. Example: 100. At least one bound is required."
            list :allowedValues, item: :literal, example: %w[active pending], visible: { rule: "in_list" },
              description: "Exact values the source must match (e.g. active, pending). At least one is required."
            flag :caseSensitive, default: true, visible: { rule: "in_list" },
              description: "When on, list comparison is case-sensitive. Off treats Active and active as the same."
            literal :postalCountry, default: "US", placeholder: true, visible: { rule: "postal_code" },
              description: "ISO alpha-2 country whose postal-code pattern is applied (US, CN, GB, CA, DE, FR, JP, AU, NL, IN, BR, IT, ES, KR, SG)."
            list :urlSchemes, item: :literal, default: %w[https http], visible: { rule: "url" },
              description: "Allowed URL schemes. Default https and http. javascript: is never accepted unless listed (do not list it)."
            literal :dateFormat, default: "%Y-%m-%d", placeholder: true, visible: { rule: %w[date date_range] },
              description: "strptime pattern used to parse the date (e.g. %Y-%m-%d or %d/%m/%Y)."
            enum :ipVersion, IP_VERSIONS, default: "any", visible: { rule: "ip_address" },
              description: "Require IPv4 (v4), IPv6 (v6), or either (any)."
            literal :minDate, default: "", placeholder: true, visible: { rule: "date_range" },
              description: "Inclusive lower date as YYYY-MM-DD, today, or tomorrow. Blank is an open lower bound."
            literal :maxDate, default: "", placeholder: true, visible: { rule: "date_range" },
              description: "Inclusive upper date as YYYY-MM-DD, today, or tomorrow. Blank is an open upper bound."
            flag :allowBlank, default: false,
              description: "Treat a blank source as valid (except the required rule, which always rejects blank)."
            enum :onInvalid, ON_INVALID, default: "fail",
              description: "fail stops the flowchart and shows the error; flag only writes resultVar false so a later step can branch."
            literal :errorField, default: "", placeholder: true,
              description: "Form field name attached to the error so the input can be highlighted (e.g. email). Blank is unscoped."
            localized_text :message, group: :advanced,
              description: "Custom localized error shown to the submitter. Blank uses the per-rule default under flowchart_runtime.errors.validate_value."
            output :resultVar, default: "valid",
              description: "Context variable set to true when the value is valid and false when it is not."
            output :normalizedVar, default: "normalized_value", group: :advanced,
              description: "Context variable that receives the canonical value when valid (e.g. lowercase email, E.164 phone)."
            requires :pattern, when: { rule: "regex" }

            validate do |_cfg, errors|
              validate_phone_country(errors)
              validate_pattern(errors)
              validate_range_bounds(errors)
              validate_allowed_values(errors)
              validate_postal_country(errors)
              validate_url_schemes(errors)
              validate_error_field(errors)
              validate_length_bounds(errors)
              validate_date_range_bounds(errors)
            end
          end

          def generate_body
            lines = [
              "check = FlowchartRuntime::ValueValidator.check(#{check_args})",
              assign(:resultVar, "check[:valid]"),
              assign(:normalizedVar, "check[:normalized]")
            ]
            unless value(:onInvalid).to_s == "flag"
              lines << "unless check[:valid]"
              lines << "  #{invalid_return_line}"
              lines << "end"
            end
            lines << "true"
            body(attempt('"validate_value.failed"', FlowchartRuntime::ValueValidator::Error) { lines })
          end

          private

          def check_args
            parts = [read(:sourceVariable), "rule: #{read(:rule)}"]
            parts.concat(rule_kwargs)
            parts << "allow_blank: true" if value(:allowBlank)
            parts.join(", ")
          end

          def rule_kwargs
            case value(:rule).to_s
            when "phone"
              country = value(:phoneCountry).to_s
              country.empty? ? [] : ["phone_country: #{read(:phoneCountry)}"]
            when "regex"
              ["pattern: #{read(:pattern)}"]
            when "length"
              opts = []
              opts << "min_length: #{read(:minLength)}" unless value(:minLength).to_i == 1
              opts << "max_length: #{read(:maxLength)}" unless value(:maxLength).to_i == 255
              opts
            when "range"
              opts = []
              opts << "min_value: #{read(:minValue)}" unless value(:minValue).nil?
              opts << "max_value: #{read(:maxValue)}" unless value(:maxValue).nil?
              opts
            when "in_list"
              opts = ["allowed_values: #{read(:allowedValues)}"]
              opts << "case_sensitive: false" unless value(:caseSensitive)
              opts
            when "postal_code"
              country = value(:postalCountry).to_s
              country.empty? || country == "US" ? [] : ["postal_country: #{read(:postalCountry)}"]
            when "url"
              schemes = Array(value(:urlSchemes)).map(&:to_s)
              schemes.empty? || schemes == %w[https http] ? [] : ["url_schemes: #{read(:urlSchemes)}"]
            when "date", "date_range"
              opts = []
              format = value(:dateFormat).to_s
              opts << "date_format: #{read(:dateFormat)}" unless format.empty? || format == "%Y-%m-%d"
              if value(:rule).to_s == "date_range"
                opts << "min_date: #{read(:minDate)}" unless value(:minDate).to_s.empty?
                opts << "max_date: #{read(:maxDate)}" unless value(:maxDate).to_s.empty?
              end
              opts
            when "ip_address"
              version = value(:ipVersion).to_s
              version.empty? || version == "any" ? [] : ["ip_version: #{read(:ipVersion)}"]
            else
              []
            end
          end

          def invalid_return_line
            field = value(:errorField).to_s.strip
            rule = value(:rule).to_s
            raise_unsafe_value!(:rule) unless RULES.include?(rule)

            field_arg = ", field: #{read(:errorField)}" unless field.empty?
            if value(:message).present?
              %(return FlowchartRuntime::Step.fail_message(ctx, #{read(:message)}, code: :"validate_value.#{rule}"#{field_arg}))
            else
              %(return FlowchartRuntime::Step.fail(ctx, :"validate_value.#{rule}"#{field_arg}))
            end
          end

          def validate_phone_country(errors)
            country = value(:phoneCountry).to_s.strip
            return if country.empty? || FlowchartRuntime::ValueValidator.valid_phone_country?(country)

            errors.add(:phoneCountry, :invalid_phone_country)
          end

          def validate_pattern(errors)
            return unless value(:rule).to_s == "regex"

            pattern = value(:pattern).to_s
            FlowchartRuntime::Regex.compile(pattern)
          rescue FlowchartRuntime::Regex::Error
            errors.add(:pattern, :invalid_pattern)
          end

          def validate_range_bounds(errors)
            return unless value(:rule).to_s == "range"

            min = value(:minValue)
            max = value(:maxValue)
            if min.nil? && max.nil?
              errors.add(:minValue, :range_bound_required)
              return
            end
            return if min.nil? || max.nil? || min.to_f <= max.to_f

            errors.add(:maxValue, :min_greater_than_max)
          end

          def validate_date_range_bounds(errors)
            return unless value(:rule).to_s == "date_range"

            min = value(:minDate).to_s.strip
            max = value(:maxDate).to_s.strip
            if min.empty? && max.empty?
              errors.add(:minDate, :range_bound_required)
              return
            end

            lo = parse_bound(min)
            hi = parse_bound(max)
            errors.add(:minDate, :invalid_date_bound) if min.present? && lo.nil?
            errors.add(:maxDate, :invalid_date_bound) if max.present? && hi.nil?
            return if lo.nil? || hi.nil? || lo <= hi

            errors.add(:maxDate, :min_greater_than_max)
          end

          def parse_bound(text)
            return nil if text.empty?
            return Date.current if text.casecmp("today").zero?
            return Date.current + 1 if text.casecmp("tomorrow").zero?

            Date.iso8601(text)
          rescue Date::Error, ArgumentError
            begin
              Date.parse(text)
            rescue Date::Error, ArgumentError, TypeError
              nil
            end
          end

          def validate_allowed_values(errors)
            return unless value(:rule).to_s == "in_list"
            return if Array(value(:allowedValues)).any?

            errors.add(:allowedValues, :empty_list)
          end

          def validate_postal_country(errors)
            return unless value(:rule).to_s == "postal_code"
            return if FlowchartRuntime::ValueValidator.supported_postal_country?(value(:postalCountry))

            errors.add(:postalCountry, :unsupported_postal_country)
          end

          def validate_url_schemes(errors)
            return unless value(:rule).to_s == "url"
            return if Array(value(:urlSchemes)).any?

            errors.add(:urlSchemes, :empty_list)
          end

          def validate_error_field(errors)
            name = value(:errorField).to_s.strip
            return if name.empty? || FIELD_FORMAT.match?(name)

            errors.add(:errorField, :invalid_identifier)
          end

          def validate_length_bounds(errors)
            return unless value(:rule).to_s == "length"
            return if value(:minLength).to_i <= value(:maxLength).to_i

            errors.add(:maxLength, :min_greater_than_max)
          end
        end
      end
    end
  end
end
