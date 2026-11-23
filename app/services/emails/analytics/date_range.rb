# frozen_string_literal: true

module Emails
  module Analytics
    # Caps a user-supplied analytics window so `since`/`until` query params
    # cannot expand every calendar day from year 1 to 9999 into RAM, or scan
    # an unbounded message table for CSV.
    module DateRange
      MAX_SPAN_DAYS = 366

      def self.clamp(since, until_date, max_days: MAX_SPAN_DAYS)
        cap = Time.current.end_of_day
        until_time = [until_date.to_time, cap].min
        since_time = since.to_time
        since_time, until_time = until_time, since_time if since_time > until_time
        until_time = cap if until_time > cap

        earliest = (until_time.to_date - max_days).beginning_of_day
        since_time = earliest if since_time < earliest

        [since_time, until_time]
      end
    end
  end
end
