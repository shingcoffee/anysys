# frozen_string_literal: true

module Emails
  module SendActivities
    # Single place that understands the (deliberately small) RRULE subset this
    # app supports: FREQ + optional INTERVAL/COUNT/UNTIL. Used by both
    # Campaign's model-level format validation and StartSendActivity's occurrence
    # arithmetic so the two can never drift out of sync.
    module RecurrenceRule
      SUPPORTED_FREQS = %w[DAILY WEEKLY MONTHLY HOURLY].freeze
      ALLOWED_PARTS    = %w[FREQ INTERVAL COUNT UNTIL].freeze

      Invalid = Class.new(StandardError)

      # @return [Hash{String=>String}, nil] parsed parts, or nil for a blank rule
      # @raise [Invalid] if the rule is present but malformed
      def self.parse(rrule)
        return nil if rrule.blank?

        parts = rrule.to_s.split(";").each_with_object({}) do |part, h|
          k, v = part.split("=", 2)
          h[k] = v
        end
        validate!(parts)
        parts
      end

      def self.valid?(rrule)
        parse(rrule)
        true
      rescue Invalid
        false
      end

      def self.validate!(parts)
        raise Invalid, "unsupported FREQ" unless SUPPORTED_FREQS.include?(parts["FREQ"])

        extra = parts.keys - ALLOWED_PARTS
        raise Invalid, "unsupported part(s): #{extra.join(', ')}" if extra.any?
        raise Invalid, "INTERVAL must be a positive integer" if parts["INTERVAL"] && !positive_integer?(parts["INTERVAL"])
        raise Invalid, "COUNT must be a positive integer" if parts["COUNT"] && !positive_integer?(parts["COUNT"])
        raise Invalid, "UNTIL is not parseable" if parts["UNTIL"] && parse_until(parts["UNTIL"]).nil?
      end

      def self.positive_integer?(str)
        str.to_s.match?(/\A\d+\z/) && str.to_i.positive?
      end

      # Parses the two RRULE UNTIL forms this app accepts: date-only (YYYYMMDD,
      # interpreted as end-of-day in `zone`) and UTC date-time (YYYYMMDDTHHMMSSZ).
      # @return [ActiveSupport::TimeWithZone, nil]
      def self.parse_until(until_str, zone: "UTC")
        tz = ActiveSupport::TimeZone[zone] || ActiveSupport::TimeZone["UTC"]

        case until_str.to_s
        when /\A\d{8}\z/
          tz.parse(until_str).end_of_day
        when /\A\d{8}T\d{6}Z\z/
          Time.strptime(until_str, "%Y%m%dT%H%M%SZ").in_time_zone(tz)
        end
      rescue ArgumentError, TypeError
        nil
      end

      # Rewrites a valid rule's COUNT to `new_count`, preserving the order and
      # value of every other part. No-op if the rule has no COUNT.
      def self.with_count(rrule, new_count)
        return rrule unless rrule.to_s.include?("COUNT=")

        rrule.split(";").map do |part|
          k, = part.split("=", 2)
          k == "COUNT" ? "COUNT=#{new_count}" : part
        end.join(";")
      end
    end
  end
end
