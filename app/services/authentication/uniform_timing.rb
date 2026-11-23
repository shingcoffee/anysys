# frozen_string_literal: true

module Authentication
  # Pads a response whose work depends on whether an address has an account
  # (new sign-up, existing member, nobody) to one minimum duration, so the
  # branch taken cannot be timed. Start the clock before the email lookup and
  # pad after the transaction commits: it never waits while holding a lock.
  module UniformTiming
    # Seconds. Must exceed the slowest branch: creating the account.
    FLOOR = 0.4

    module_function

    def start
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def pad(started_at)
      return unless started_at.is_a?(Numeric)
      return if ActiveRecord::Base.connection.transaction_open?

      remaining = FLOOR - (start - started_at)
      sleep(remaining) if remaining.positive?
    end
  end
end
