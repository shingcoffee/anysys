# frozen_string_literal: true

module FlowchartRuntime
  # Parses a deadline and reports whether the reference time has passed it.
  module Deadline
    class Error < StandardError; end

    MAX_GRACE_PERIOD_SECONDS = 31_536_000
    FORMATS = %w[iso8601 rfc2822 auto].freeze

    module_function

    def check(deadline:, format: "auto", reference: nil, grace_seconds: 0, warning_seconds: 0)
      now = reference.nil? || reference == "" ? Time.current : coerce_time!(reference, "auto")
      due = coerce_time!(deadline, format)
      grace = Integer(grace_seconds, exception: false)
      raise Error, "grace period is invalid" if grace.nil? || grace.negative? || grace > MAX_GRACE_PERIOD_SECONDS
      warning = Integer(warning_seconds, exception: false)
      raise Error, "warning period is invalid" if warning.nil? || warning.negative? || warning > MAX_GRACE_PERIOD_SECONDS

      diff = (due - now).to_f
      remaining = [diff, 0].max
      breached = now > (due + grace)
      {
        status: {
          passed: diff <= 0,
          remaining_seconds: remaining,
          overdue_seconds: diff.negative? ? diff.abs : 0
        },
        breached: breached,
        at_risk: !breached && warning.positive? && remaining <= warning
      }
    end

    def coerce_time!(value, format)
      return value.to_time if value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(ActiveSupport::TimeWithZone)
      return value.to_time if value.is_a?(Date)
      raise Error, "deadline is invalid" if value.nil? || value.to_s.strip.empty?

      text = value.to_s
      case format.to_s
      when "iso8601" then Time.iso8601(text)
      when "rfc2822" then Time.rfc2822(text)
      else Time.parse(text)
      end
    rescue ArgumentError, TypeError
      raise Error, "deadline is invalid"
    end
    private_class_method :coerce_time!
  end
end
