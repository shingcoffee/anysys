# frozen_string_literal: true

module Sms
  # Each admitted ledger row is its reservation. Never separate phone-window
  # and daily-cap checks from the insertion under the customer's lock.
  class Quota
    def self.synchronize(customer)
      customer.with_lock do
        # SQLite's deferred transactions have no SELECT FOR UPDATE; acquire its
        # write lock before quota/idempotency reads. PostgreSQL locks the row.
        Customer.where(id: customer.id).update_all("id = id")
        yield
      end
    end

    def self.check_rate_limit!(customer_id:, to:, windows:)
      now = Time.current
      lookback = windows.map { |_name, seconds, _limit| seconds }.max
      return unless lookback

      recent = Message.rate_limit_window(customer_id: customer_id, to: to, since: now - lookback)
      windows.each do |name, seconds, limit|
        raise Errors::RateLimited.new(window: name) if recent.count { |time| time >= now - seconds } >= limit
      end
    end

    def self.check_daily!(customer)
      count = Message.where(customer_id: customer.id).where.not(status: %w[suppressed failed expired])
                     .where(created_at: Time.current.beginning_of_day..).count
      return if count < Activities::Send.daily_cap_for(customer)

      raise Errors::DailyCapExceeded, I18n.t("admin_modules.sms.errors.daily_cap_exceeded")
    end
  end
end
