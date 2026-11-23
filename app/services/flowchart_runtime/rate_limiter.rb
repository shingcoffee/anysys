# frozen_string_literal: true

module FlowchartRuntime
  # Fixed-window limiter. Each check performs one atomic increment of `cost`
  # on Authentication::Throttle.store (Solid Cache / MemoryStore), so concurrent
  # runs cannot both take the last slot.
  module RateLimiter
    class Error < StandardError; end

    SCOPES = %w[global user ip custom].freeze
    THROTTLE_PREFIX = "auth_throttle:"

    module_function

    def check(ctx, name, capacity:, window:, scope: "global", scope_value: nil, cost: 1)
      label = name.to_s.strip
      raise Error, "name is required" if label.empty?

      cap = Integer(capacity, exception: false)
      win = Integer(window, exception: false)
      tokens = Integer(cost, exception: false)
      raise Error, "capacity must be positive" unless cap&.positive?
      raise Error, "window must be positive" unless win&.positive?
      raise Error, "cost must be positive" unless tokens&.positive?

      bucket = (Time.current.to_i / win) * win
      key = CacheKey.scoped(ctx[:customer_id], *key_parts(ctx, label, scope, scope_value, win, bucket))
      denied = consume(key, tokens, cap, win)
      allowed = !denied
      { allowed: allowed, retry_after: allowed ? 0 : seconds_until_reset(win) }
    end

    def allow?(ctx, name, capacity:, window:, scope: "global", scope_value: nil, cost: 1)
      check(ctx, name, capacity: capacity, window: window, scope: scope,
            scope_value: scope_value, cost: cost)[:allowed]
    end

    def consume(key, tokens, capacity, window)
      store = ::Authentication::Throttle.store
      cache_key = "#{THROTTLE_PREFIX}#{key}"
      period = window.seconds
      count = store.increment(cache_key, tokens, expires_in: period)
      if count.nil?
        count = if store.write(cache_key, tokens, expires_in: period, unless_exist: true)
          tokens
        else
          store.increment(cache_key, tokens, expires_in: period) || tokens
        end
      end
      count.to_i > capacity
    end
    private_class_method :consume

    def key_parts(ctx, label, scope, scope_value, win, bucket)
      parts = ["rate_limiter", label]
      case scope.to_s
      when "user"
        parts << "u:#{ctx && ctx[:current_user_id].presence || 'anonymous'}"
      when "ip"
        parts << "ip:#{ctx && ctx[:request_ip].presence || 'unknown'}"
      when "custom"
        token = scope_value.to_s.strip
        raise Error, "scope is required" if token.empty?

        parts << "x:#{token}"
      when "global", ""
        nil
      else
        raise Error, "unknown scope"
      end
      parts + [win, bucket]
    end
    private_class_method :key_parts

    def seconds_until_reset(window)
      remainder = Time.current.to_i % window
      remainder.zero? ? window : window - remainder
    end
    private_class_method :seconds_until_reset
  end
end
