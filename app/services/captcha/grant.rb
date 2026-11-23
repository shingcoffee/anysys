# frozen_string_literal: true

module Captcha
  class Grant
    PREFIX = "captcha:grant"
    WINDOW_PREFIX = "captcha:window"

    class << self
      def store(ip:, pattern:, ttl:)
        return if ttl.to_i <= 0

        cache.write(key(ip, pattern), true, expires_in: ttl)
      end

      def active?(ip:, pattern:)
        cache.read(key(ip, pattern)).present?
      end

      def mark_window(ip:, pattern:, period:)
        cache.write(
          window_key(ip, pattern),
          Time.current.to_i + period.to_i,
          expires_in: [period.to_i, 1].max,
          unless_exist: true
        )
      end

      def ttl_for(rule, ip:)
        return Captcha::ThrottlePresets::EVERY_HIT_GRANT if rule.every_hit

        full = (rule.period_seconds || Captcha::ThrottlePresets::DEFAULT_PERIOD.to_i).to_i
        ends_at = cache.read(window_key(ip, rule.pattern)).to_i
        remaining = ends_at.positive? ? (ends_at - Time.current.to_i) : full
        [remaining, 1].max.seconds
      end

      def cache
        Captcha::ThrottleRegistry.store
      end

      private

      def key(ip, pattern)
        "#{PREFIX}:#{ip}:#{pattern}"
      end

      def window_key(ip, pattern)
        "#{WINDOW_PREFIX}:#{ip}:#{pattern}"
      end
    end
  end
end
