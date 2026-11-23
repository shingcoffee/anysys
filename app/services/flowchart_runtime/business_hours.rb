# frozen_string_literal: true

module FlowchartRuntime
  module BusinessHours
    class Error < StandardError; end

    DAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
    SEGMENT = /(?:[01]\d|2[0-3]):[0-5]\d/
    RANGE_RE = /\A#{SEGMENT}-#{SEGMENT}\z/
    WINDOWS_RE = /\A#{SEGMENT}-#{SEGMENT}(?:,#{SEGMENT}-#{SEGMENT})*\z/
    MAX_LOOKAHEAD_DAYS = 366

    module_function

    def open?(schedule:, at:, timezone:, holidays: [])
      zone = resolve_timezone!(timezone)
      time = coerce_at!(at).in_time_zone(zone)
      closed_dates = holiday_dates(holidays)
      windows = day_windows(schedule, time)
      currently_open = !closed_dates.include?(time.to_date) && within_windows?(time, windows)
      next_at = currently_open ? nil : next_open_at(schedule, time, closed_dates)

      {
        open: currently_open,
        next_open_at: next_at,
        minutes_until_open: minutes_until(time, currently_open, next_at)
      }
    end

    def add_minutes(schedule:, at:, timezone:, holidays: [], minutes: 0)
      zone = resolve_timezone!(timezone)
      cursor = coerce_at!(at).in_time_zone(zone)
      remaining = Integer(minutes, exception: false)
      raise Error, "minutes is invalid" if remaining.nil? || remaining.negative?
      return cursor if remaining.zero?

      closed_dates = holiday_dates(holidays)
      days_scanned = 0
      while remaining.positive?
        raise Error, "business minutes exceed schedule horizon" if days_scanned > MAX_LOOKAHEAD_DAYS

        windows = day_windows(schedule, cursor)
        if closed_dates.include?(cursor.to_date) || windows.empty?
          cursor = next_open_at(schedule, cursor, closed_dates)
          raise Error, "no open window" if cursor.nil?

          days_scanned += 1
          next
        end

        window = windows.find do |range|
          cursor < cursor.change(hour: range[:end_h], min: range[:end_m], sec: 0)
        end
        if window.nil?
          cursor = next_open_at(schedule, cursor, closed_dates)
          raise Error, "no open window" if cursor.nil?

          days_scanned += 1
          next
        end

        start_at = cursor.change(hour: window[:start_h], min: window[:start_m], sec: 0)
        end_at = cursor.change(hour: window[:end_h], min: window[:end_m], sec: 0)
        cursor = start_at if cursor < start_at
        available = ((end_at - cursor) / 60.0).floor
        return cursor + remaining.minutes if remaining <= available

        remaining -= available
        cursor = end_at
      end

      cursor
    end

    def valid_windows?(raw)
      parse_windows(raw).any?
    rescue Error
      false
    end

    def resolve_timezone!(timezone)
      ActiveSupport::TimeZone[timezone] || TZInfo::Timezone.get(timezone.to_s)
    rescue TZInfo::InvalidTimezoneIdentifier
      raise Error, "timezone is invalid"
    end

    def coerce_at!(at)
      return Time.current if at.nil? || at == ""
      return at if at.respond_to?(:in_time_zone)

      Time.parse(at.to_s)
    rescue ArgumentError, TypeError
      raise Error, "time is invalid"
    end

    def holiday_dates(holidays)
      entries = holidays.is_a?(Hash) ? holidays.keys : Array(holidays)
      entries.flat_map do |entry|
        date = entry.is_a?(Hash) ? (entry["date"] || entry[:date] || entry.keys.first) : entry
        next [] if date.blank?

        [date.is_a?(Date) ? date : Date.iso8601(date.to_s)]
      end
    rescue Date::Error
      raise Error, "holiday date is invalid"
    end

    def day_windows(schedule, time)
      table = schedule.to_h
      raw = table[time.strftime("%A").downcase] || table[time.strftime("%A").downcase.to_sym]
      parse_windows(raw)
    end

    def parse_windows(raw)
      value =
        if raw.is_a?(Hash)
          start_at = raw["start"] || raw[:start]
          end_at = raw["end"] || raw[:end]
          (start_at && end_at) ? "#{start_at}-#{end_at}" : nil
        else
          raw.to_s.presence
        end
      return [] unless value&.match?(WINDOWS_RE)

      windows = value.split(",").map { |part| parse_one_range(part) }
      windows.sort_by! { |window| [window[:start_h], window[:start_m]] }
      windows.each_cons(2) do |left, right|
        left_end = (left[:end_h] * 60) + left[:end_m]
        right_start = (right[:start_h] * 60) + right[:start_m]
        raise Error, "schedule windows overlap" if left_end > right_start
      end
      windows
    end

    def parse_one_range(value)
      raise Error, "schedule window is invalid" unless value&.match?(RANGE_RE)

      start_s, end_s = value.split("-")
      raise Error, "schedule window is inverted" unless start_s < end_s

      { start_h: start_s[0, 2].to_i, start_m: start_s[3, 2].to_i, end_h: end_s[0, 2].to_i, end_m: end_s[3, 2].to_i }
    end

    def within_windows?(time, windows)
      windows.any? do |range|
        start_at = time.change(hour: range[:start_h], min: range[:start_m], sec: 0)
        end_at = time.change(hour: range[:end_h], min: range[:end_m], sec: 0)
        time.between?(start_at, end_at)
      end
    end

    def next_open_at(schedule, time, closed_dates)
      (0..MAX_LOOKAHEAD_DAYS).each do |offset|
        probe = time + offset.days
        next if closed_dates.include?(probe.to_date)

        day_windows(schedule, probe).each do |range|
          start_at = probe.change(hour: range[:start_h], min: range[:start_m], sec: 0)
          next if offset.zero? && time >= start_at

          return start_at
        end
      end
      nil
    end

    def minutes_until(time, currently_open, next_at)
      return 0 if currently_open
      return nil if next_at.nil?

      ((next_at - time) / 60.0).ceil
    end

    private_class_method :resolve_timezone!, :coerce_at!, :holiday_dates, :day_windows, :parse_windows,
      :parse_one_range, :within_windows?, :next_open_at, :minutes_until
  end
end
