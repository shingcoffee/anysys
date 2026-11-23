# frozen_string_literal: true

module Authentication
  # Shared-store rate limiter. Originally for auth flows (login, MFA verify,
  # password reset, confirmation resend) and still namespaced `auth_throttle:`,
  # but it is the app's general-purpose limiter — speech-to-text caps its paid
  # vendor calls through it too, so callers pass a fully-qualified `key:`.
  # Backed by Rails.cache — solid_cache in production, so
  # the limit is enforced across ALL app workers (unlike a per-process
  # MemoryStore). On breach the caller renders a generic response (no
  # enumeration) and records an audit `throttled` event.
  class Throttle
    # Every second-factor surface — verify, enrol, disable, and the member
    # equivalents — shares one bucket per user so attempts against the same
    # TOTP secret cannot be spread across endpoints to multiply the budget.
    # Defined once here because five call sites previously repeated the key
    # and the limits as literals, where a drift in any one of them silently
    # widens the brute-force window.
    MFA_LIMIT  = 5
    MFA_PERIOD = 15.minutes

    class << self
      def mfa(user)
        new(key: "mfa:#{user.id}", limit: MFA_LIMIT, period: MFA_PERIOD)
      end

      # The NullStore fallback is test-only: config/environments/test.rb sets
      # `cache_store = :null_store` (a store that silently drops writes, so the
      # limiter could never count), while production sets
      # `cache_store = :solid_cache_store` — a DB-backed store shared by every
      # worker, which is what makes the limit global rather than per-process.
      # A per-process MemoryStore here would silently weaken the limit by the
      # number of workers, so this branch must never be reachable in
      # production. Overridable for specs.
      attr_writer :store

      def store
        @store ||= if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
                     ActiveSupport::Cache::MemoryStore.new
        else
                     Rails.cache
        end
      end

      def reset_store!
        @store = nil
      end
    end

    def initialize(key:, limit:, period:)
      @cache_key = "auth_throttle:#{key}"
      @limit     = limit
      @period    = period
    end

    # Two policies use this limiter and they need different primitives:
    #
    #   * count-every-attempt (sign-in, password reset, email flood) — use
    #     #hit!, which increments and compares in one atomic step. The
    #     read-then-increment pair below is not safe for these callers: N
    #     concurrent requests all read the same under-limit count and all
    #     pass, so the effective cap scales with concurrency.
    #   * count-failures-only, clear-on-success (the MFA surfaces) — use
    #     #exceeded? / #record_failure / #clear. These cannot be fused,
    #     because a correct code must reset the counter rather than consume
    #     from it. Concurrent attempts are still each counted, so the residual
    #     slack is one window's worth of in-flight requests.
    #
    # Registers the attempt and reports whether it exceeded the limit.
    # `increment` is atomic in solid_cache and MemoryStore alike.
    def hit!
      count = self.class.store.increment(@cache_key, 1, expires_in: @period)
      count = seed_counter if count.nil?

      count.to_i > @limit
    end

    def exceeded?
      count >= @limit
    end

    def record_failure
      self.class.store.increment(@cache_key, 1, expires_in: @period) || seed_counter
    end

    def clear
      self.class.store.delete(@cache_key)
    end

    def count
      self.class.store.read(@cache_key).to_i
    end

    private

    # `increment` returns nil for a key that does not exist yet, so the first
    # attempt in a window has to seed it. Re-increment if another worker won
    # the race and seeded first, otherwise that worker's count is clobbered
    # back to 1.
    def seed_counter
      if self.class.store.write(@cache_key, 1, expires_in: @period, unless_exist: true)
        1
      else
        self.class.store.increment(@cache_key, 1, expires_in: @period) || 1
      end
    end
  end
end
