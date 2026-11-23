# frozen_string_literal: true

require "fugit"

module FlowchartRuntime
  # Next-run dates for the next_occurrence step.
  module Recurrence
    class Error < StandardError; end

    FREQUENCIES = %w[daily weekly monthly yearly cron].freeze
    WEEKDAYS = %w[mon tue wed thu fri sat sun].freeze
    MONTH_END_POLICIES = %w[clamp skip].freeze
    BUSINESS_ADJUSTS = %w[none next_business_day previous_business_day].freeze
    RETURNS = %w[first list].freeze
    WEEKDAY_WDAY = {
      "mon" => 1, "tue" => 2, "wed" => 3, "thu" => 4, "fri" => 5, "sat" => 6, "sun" => 0
    }.freeze
    TIME_OF_DAY_RE = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/
    MAX_STEPS = 2_000

    module_function

    def valid_weekday?(value)
      WEEKDAYS.include?(value.to_s.downcase)
    end

    def valid_time_of_day?(value)
      text = value.to_s
      text.empty? || TIME_OF_DAY_RE.match?(text)
    end

    def next_occurrences(frequency:, interval: 1, start_at: nil, from: nil, weekdays: [],
                         day_of_month: 0, month_end_policy: "clamp", cron_expression: "",
                         time_of_day: "", timezone: nil, business_day_adjust: "none",
                         returns: "first", count: 5, until_at: nil)
      name = frequency.to_s
      raise Error, "unsupported frequency" unless FREQUENCIES.include?(name)

      zone_name = timezone.to_s.presence || Time.zone&.name || "UTC"
      zone = Time.find_zone(zone_name) || ActiveSupport::TimeZone[zone_name]
      raise Error, "invalid timezone" unless zone

      Time.use_zone(zone) do
        origin = coerce_time!(start_at, zone) || Time.current
        after = coerce_time!(from, zone) || Time.current
        stop = coerce_time!(until_at, zone)
        needed = returns.to_s == "list" ? clamp_count(count) : 1
        values = if name == "cron"
          cron_series(cron_expression, zone_name, after, stop, needed, business_day_adjust, zone)
        else
          calendar_series(
            name, origin, after, stop, needed,
            interval: interval.to_i, weekdays: weekdays, day_of_month: day_of_month.to_i,
            month_end_policy: month_end_policy, time_of_day: time_of_day,
            business_day_adjust: business_day_adjust, zone: zone
          )
        end
        return { value: nil, error: :no_occurrence } if values.empty?

        { value: (returns.to_s == "list" ? values : values.first), error: nil }
      end
    rescue Error => error
      return { value: nil, error: :invalid_anchor } if error.message == "invalid_anchor"

      raise
    end

    def coerce_time!(value, zone)
      return nil if value.nil? || value == ""

      time = if value.respond_to?(:in_time_zone)
        value.in_time_zone(zone)
      else
        zone.parse(value.to_s) || Time.zone.parse(value.to_s)&.in_time_zone(zone)
      end
      raise Error, "invalid_anchor" unless time

      time
    rescue ArgumentError, TypeError
      raise Error, "invalid_anchor"
    end
    private_class_method :coerce_time!

    def clamp_count(count)
      n = count.to_i
      return 1 if n < 1
      n > 366 ? 366 : n
    end
    private_class_method :clamp_count

    def cron_series(expression, timezone, after, stop, needed, adjust, zone)
      parsed = Schedule.parse_cron(expression, timezone: timezone)
      raise Error, "invalid cron expression" unless parsed

      values = []
      cursor = after
      steps = 0
      while values.size < needed && steps < MAX_STEPS
        nxt = parsed.next_time(cursor)
        break unless nxt

        cursor = nxt.to_t
        candidate = apply_business_day(cursor.in_time_zone(zone), adjust)
        steps += 1
        next if candidate <= after || (values.any? && candidate <= values.last)
        break if stop && candidate > stop

        values << candidate
      end
      values
    end
    private_class_method :cron_series

    def calendar_series(frequency, origin, after, stop, needed, interval:, weekdays:, day_of_month:,
                        month_end_policy:, time_of_day:, business_day_adjust:, zone:)
      interval = interval < 1 ? 1 : interval
      values = []
      index = start_index(frequency, origin, after, interval, weekdays)
      steps = 0
      while values.size < needed && steps < MAX_STEPS
        stamp = occurrence_at(
          frequency, index, origin, interval, weekdays, day_of_month, month_end_policy, zone
        )
        index += 1
        steps += 1
        next if stamp.nil?

        candidate = apply_time_of_day(stamp, time_of_day, zone)
        candidate = apply_business_day(candidate, business_day_adjust)
        next if candidate <= after || (values.any? && candidate <= values.last)
        break if stop && candidate > stop

        values << candidate
      end
      values
    end
    private_class_method :calendar_series

    # Skips whole periods before `after`, keeping one period plus the 3-day
    # business-day/time-of-day shift as margin so no occurrence is missed.
    def start_index(frequency, origin, after, interval, weekdays)
      days = (after.to_date - origin.to_date).to_i - 3
      return 0 if days <= 0

      periods = case frequency
      when "daily" then days / interval
      when "weekly" then (days / 7 / interval - 1) * weekly_offsets(weekdays, origin).size
      when "monthly" then (month_span(origin, after) / interval) - 1
      when "yearly" then ((after.year - origin.year) / interval) - 1
      else 0
      end
      [periods, 0].max
    end
    private_class_method :start_index

    def month_span(origin, after)
      (after.year * 12 + after.month) - (origin.year * 12 + origin.month)
    end
    private_class_method :month_span

    def weekly_offsets(weekdays, origin)
      selected = Array(weekdays).map { |day| WEEKDAY_WDAY[day.to_s.downcase] }.compact
      selected = [origin.wday] if selected.empty?
      selected.map { |wday| wday.zero? ? 6 : wday - 1 }.uniq.sort
    end
    private_class_method :weekly_offsets

    def occurrence_at(frequency, index, origin, interval, weekdays, day_of_month, policy, zone)
      case frequency
      when "daily" then origin + (index * interval).days
      when "weekly" then weekly_at(index, origin, interval, weekdays, zone)
      when "monthly" then monthly_at(index, origin, interval, day_of_month, policy, zone)
      when "yearly" then yearly_at(index, origin, interval, day_of_month, policy, zone)
      end
    end
    private_class_method :occurrence_at

    def weekly_at(index, origin, interval, weekdays, zone)
      offsets = weekly_offsets(weekdays, origin)
      week_offset = (index / offsets.size) * interval
      day_index = index % offsets.size
      week_start = origin.to_date.beginning_of_week(:monday) + week_offset.weeks
      date = week_start + offsets[day_index].days
      return nil if date < origin.to_date

      combine(date, origin, zone)
    end
    private_class_method :weekly_at

    def monthly_at(index, origin, interval, day_of_month, policy, zone)
      month = Date.new(origin.year, origin.month, 1) >> (index * interval)
      date = month_date(month.year, month.month, day_of_month, origin.day, policy)
      date && combine(date, origin, zone)
    end
    private_class_method :monthly_at

    def yearly_at(index, origin, interval, day_of_month, policy, zone)
      year = origin.year + (index * interval)
      date = month_date(year, origin.month, day_of_month, origin.day, policy)
      date && combine(date, origin, zone)
    end
    private_class_method :yearly_at

    def month_date(year, month, day_of_month, origin_day, policy)
      day = day_of_month.zero? ? origin_day : day_of_month
      return Date.new(year, month, -1) if day == -1
      return Date.new(year, month, day) if Date.valid_date?(year, month, day)
      return Date.new(year, month, -1) if policy.to_s == "clamp"

      nil
    end
    private_class_method :month_date

    def combine(date, origin, zone)
      zone.local(date.year, date.month, date.day, origin.hour, origin.min, origin.sec)
    end
    private_class_method :combine

    def apply_time_of_day(stamp, time_of_day, zone)
      text = time_of_day.to_s
      return stamp if text.empty?

      hour, min = text.split(":").map(&:to_i)
      zone.local(stamp.year, stamp.month, stamp.day, hour, min, 0)
    end
    private_class_method :apply_time_of_day

    def apply_business_day(stamp, adjust)
      case adjust.to_s
      when "next_business_day"
        stamp += 1.day while weekend?(stamp)
        stamp
      when "previous_business_day"
        stamp -= 1.day while weekend?(stamp)
        stamp
      else
        stamp
      end
    end
    private_class_method :apply_business_day

    def weekend?(stamp)
      stamp.saturday? || stamp.sunday?
    end
    private_class_method :weekend?
  end
end
