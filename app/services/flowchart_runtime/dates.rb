# frozen_string_literal: true

module FlowchartRuntime
  # Date/time arithmetic, formatting, parsing, and timezone conversion.
  module Dates
    class Error < StandardError; end

    OPERATIONS = %w[
      now add subtract difference start_of end_of age compare
      format parse convert_timezone
    ].freeze
    UNITS = %w[seconds minutes hours days weeks months years].freeze
    BUSINESS_DAY_UNITS = %w[days weeks].freeze
    DST_POLICIES = %w[preserve_wall preserve_utc].freeze
    DST_BEHAVIORS = %w[raise_on_ambiguous prefer_earlier prefer_later].freeze
    OUTPUT_FORMATS = %w[iso8601 rfc3339 unix unix_ms].freeze
    SELF_FORMATTING = %w[difference format age compare].freeze
    BEGINNING = {
      "seconds" => :beginning_of_minute,
      "minutes" => :beginning_of_minute,
      "hours" => :beginning_of_hour,
      "days" => :beginning_of_day,
      "weeks" => :beginning_of_week,
      "months" => :beginning_of_month,
      "years" => :beginning_of_year
    }.freeze
    ENDING = {
      "seconds" => :end_of_minute,
      "minutes" => :end_of_minute,
      "hours" => :end_of_hour,
      "days" => :end_of_day,
      "weeks" => :end_of_week,
      "months" => :end_of_month,
      "years" => :end_of_year
    }.freeze

    module_function

    def apply(source, operation:, end_value: nil, amount: 1, unit: "days",
              format_string: "%Y-%m-%d", input_format: nil, output_format: nil,
              business_days: false, timezone_aware: false, timezone: nil,
              dst_policy: "preserve_wall", source_timezone: "UTC",
              target_timezone: "UTC", preserve_local_time: false,
              dst_behavior: "prefer_later")
      name = operation.to_s
      raise Error, "unsupported operation" unless OPERATIONS.include?(name)

      zone = resolve_zone(timezone, timezone_aware)
      result = case name
      when "now" then now_value(zone)
      when "add", "subtract"
        shift(source, name, amount, unit, business_days: business_days, zone: zone, dst_policy: dst_policy)
      when "difference" then difference(source, end_value, unit: unit, zone: zone)
      when "start_of" then boundary(source, unit, BEGINNING, zone)
      when "end_of" then boundary(source, unit, ENDING, zone)
      when "age" then age(source, end_value, zone)
      when "compare" then compare(source, end_value, zone)
      when "format" then format_source(source, format_string, zone)
      when "parse" then parse_source(source, input_format, zone)
      when "convert_timezone"
        convert_timezone(source, source_timezone: source_timezone, target_timezone: target_timezone,
                         preserve_local_time: preserve_local_time, dst_behavior: dst_behavior,
                         output_format: output_format)
      end

      return result if name == "convert_timezone" || SELF_FORMATTING.include?(name)

      apply_output_format(result, output_format)
    rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier => error
      raise Error, error.message
    end

    def resolve_zone(timezone, timezone_aware)
      name = timezone.to_s
      if name.present?
        zone = Time.find_zone(name) || ActiveSupport::TimeZone[name]
        raise Error, "invalid timezone: #{name}" unless zone

        return zone
      end

      timezone_aware ? Time.zone : nil
    end

    def now_value(zone)
      zone ? Time.current.in_time_zone(zone) : Time.current
    end

    def coerce_time(value, zone)
      raise Error, "source is required" if value.nil? || value == ""

      time = if value.respond_to?(:in_time_zone)
        zone ? value.in_time_zone(zone) : value.in_time_zone
      else
        (zone || Time.zone).parse(value.to_s)
      end
      raise Error, "invalid time" unless time

      time
    rescue ArgumentError, TypeError
      raise Error, "invalid time"
    end

    def shift(source, direction, amount, unit, business_days:, zone:, dst_policy:)
      raise Error, "unsupported unit" unless UNITS.include?(unit.to_s)

      base = coerce_time(source, zone)
      count = amount.to_i
      if business_days && BUSINESS_DAY_UNITS.include?(unit.to_s)
        return business_days_shift(base, count, unit, direction)
      end

      dst_aware_shift(base, count, unit, direction, dst_policy: dst_policy, zone: zone)
    end

    def business_days_shift(base, amount, unit, direction)
      step = direction == "add" ? 1 : -1
      days = unit.to_s == "weeks" ? amount * 5 : amount
      (1..days).inject(base) do |date, _|
        loop do
          date += step.days
          break date unless date.saturday? || date.sunday?
        end
      end
    end

    def dst_aware_shift(base, amount, unit, direction, dst_policy:, zone:)
      delta = amount.public_send(unit)
      if dst_policy.to_s == "preserve_utc"
        shifted = direction == "add" ? (base.utc + delta) : (base.utc - delta)
        return zone ? shifted.in_time_zone(zone) : shifted.in_time_zone
      end

      direction == "add" ? (base + delta) : (base - delta)
    end

    def difference(start_value, end_value, unit:, zone:)
      raise Error, "unsupported unit" unless UNITS.include?(unit.to_s)

      finish = coerce_time(end_value, zone)
      begin_at = coerce_time(start_value, zone)
      case unit.to_s
      when "seconds" then (finish - begin_at).to_i
      when "minutes" then ((finish - begin_at) / 1.minute).to_i
      when "hours" then ((finish - begin_at) / 1.hour).to_i
      when "days" then (finish.to_date - begin_at.to_date).to_i
      when "weeks" then ((finish.to_date - begin_at.to_date) / 7).to_i
      when "months" then month_span(begin_at, finish)
      when "years" then year_span(begin_at, finish)
      end
    end

    def month_span(begin_at, finish)
      (finish.year * 12 + finish.month) - (begin_at.year * 12 + begin_at.month)
    end

    def year_span(begin_at, finish)
      years = finish.year - begin_at.year
      anniversary = begin_at + years.years
      anniversary > finish ? years - 1 : years
    end

    def boundary(source, unit, mapping, zone)
      method = mapping[unit.to_s]
      raise Error, "unsupported unit" unless method

      coerce_time(source, zone).public_send(method)
    end

    def age(source, as_of, zone)
      birth = coerce_time(source, zone).to_date
      today = (as_of.nil? || as_of == "" ? now_value(zone) : coerce_time(as_of, zone)).to_date
      years = today.year - birth.year
      anniversary = birth >> (years * 12)
      anniversary > today ? years - 1 : years
    end

    def compare(source, end_value, zone)
      left = coerce_time(source, zone)
      right = coerce_time(end_value, zone)
      left <=> right
    end

    def format_source(source, format_string, zone)
      coerce_time(source, zone).strftime(format_string.to_s.presence || "%Y-%m-%d")
    end

    def parse_source(source, input_format, zone)
      text = source.to_s
      raise Error, "source is required" if text.blank?

      parse_call = lambda do
        fmt = input_format.to_s
        if fmt.present? && fmt != "iso"
          Time.zone.strptime(text, fmt)
        else
          Time.zone.parse(text)
        end
      end

      parsed = if zone
        Time.use_zone(zone, &parse_call)
      else
        parse_call.call
      end
      raise Error, "invalid time" unless parsed

      parsed
    end

    def convert_timezone(source, source_timezone:, target_timezone:, preserve_local_time:, dst_behavior:, output_format:)
      src_zone = find_zone!(source_timezone, "sourceTimezone")
      tgt_zone = find_zone!(target_timezone, "targetTimezone")
      parsed = source.is_a?(String) ? src_zone.parse(source) : coerce_time(source, src_zone)
      converted = if preserve_local_time
        preserve_local(parsed, tgt_zone, dst_behavior)
      else
        parsed.in_time_zone(tgt_zone)
      end
      apply_output_format(converted, output_format)
    end

    def preserve_local(source, tgt_zone, dst_behavior)
      tgt_zone.local(source.year, source.month, source.day, source.hour, source.min, source.sec)
    rescue TZInfo::AmbiguousTime
      case dst_behavior.to_s
      when "raise_on_ambiguous" then raise Error, "ambiguous local time"
      when "prefer_earlier" then ambiguous_pick(source, tgt_zone, :min)
      else ambiguous_pick(source, tgt_zone, :max)
      end
    end

    def ambiguous_pick(source, tgt_zone, picker)
      utc = Time.utc(source.year, source.month, source.day, source.hour, source.min, source.sec)
      periods = tgt_zone.tzinfo.periods_for_local(utc)
      period = picker == :min ? periods.min_by(&:starts_at) : periods.max_by(&:starts_at)
      ActiveSupport::TimeWithZone.new(nil, tgt_zone, utc - period.utc_total_offset)
    end

    def find_zone!(name, label)
      raise Error, "invalid #{label}: #{name}" if name.to_s.blank?

      zone = Time.find_zone(name) || ActiveSupport::TimeZone[name]
      raise Error, "invalid #{label}: #{name}" unless zone

      zone
    end

    def apply_output_format(value, format)
      fmt = format.to_s
      return value if fmt.blank?

      case fmt
      when "iso8601" then value.iso8601
      when "rfc3339" then value.rfc3339
      when "unix" then value.to_i
      when "unix_ms" then (value.to_f * 1000).to_i
      else value.strftime(fmt)
      end
    end
  end
end
