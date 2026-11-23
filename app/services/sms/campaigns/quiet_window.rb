# frozen_string_literal: true

require "tzinfo"

module Sms
  module Campaigns
    class QuietWindow
      def self.next_allowed(at:, timezone:, start_hour:, end_hour:)
        zone = TZInfo::Timezone.get(timezone)
        local = zone.to_local(at.to_time.utc)
        quiet = start_hour < end_hour ? (local.hour >= start_hour && local.hour < end_hour) :
          (local.hour >= start_hour || local.hour < end_hour)
        return at unless quiet

        date = local.to_date
        date += 1 if start_hour > end_hour && local.hour >= start_hour
        wall = Time.utc(date.year, date.month, date.day, end_hour)
        # Choose the earliest allowed future occurrence of an ambiguous end.
        # A gap moves to its first valid local minute, never guesses an offset.
        2.days.in_minutes.to_i.times do
          periods = zone.periods_for_local(wall)
          candidates = periods.map { |period| wall - period.observed_utc_offset }.select { |time| time > at }
          return candidates.min if candidates.any?
          wall += 1.minute
        end
        raise TZInfo::PeriodNotFound
      end
    end
  end
end
