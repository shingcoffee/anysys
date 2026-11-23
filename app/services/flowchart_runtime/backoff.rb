# frozen_string_literal: true

module FlowchartRuntime
  # Bounded backoff-delay arithmetic for flowchart retry steps.
  #
  # Every generated retry step routes its delay computation through this
  # facade so a flowchart configuration can never pin a worker: the attempt
  # counter, the base delay, the ceiling and the jitter percentage are all
  # validated and clamped here rather than in emitted source.
  #
  # Mirrors the bounding precedent of FlowchartRuntime::Lock
  # (MAX_TTL_SECONDS / MAX_RETRY_COUNT / MAX_SLEEP_SECONDS).
  module Backoff
    class Error < StandardError; end

    STRATEGIES        = %w[fixed linear exponential decorrelated_jitter].freeze
    MAX_DELAY_SECONDS = 60
    MAX_ATTEMPTS      = 50

    module_function

    # @param attempt [Integer] 1-based attempt number
    # @return [Float] seconds to wait before the next attempt, always within
    #   0..[max_delay, MAX_DELAY_SECONDS].min
    def delay_for(attempt, strategy:, initial_delay:, max_delay: MAX_DELAY_SECONDS,
                  jitter_percent: 0, previous_delay: nil)
      n        = cast_attempt(attempt)
      strat    = cast_strategy(strategy)
      base     = cast_seconds(initial_delay, "initial_delay")
      ceiling  = [cast_seconds(max_delay, "max_delay"), MAX_DELAY_SECONDS.to_f].min
      jitter   = cast_percent(jitter_percent)
      previous = previous_delay.nil? ? base : cast_seconds(previous_delay, "previous_delay")

      raw = case strat
            when "linear"              then base * n
            when "exponential"         then base * (2**(n - 1))
            when "decorrelated_jitter" then decorrelated(base, previous)
            else                            base
            end

      clamp(apply_jitter(clamp(raw, ceiling), jitter), ceiling)
    end

    # Total worst-case wall-clock cost of a retry policy, used to prove a
    # configuration is bounded.
    def total_delay(attempts, strategy:, initial_delay:, max_delay: MAX_DELAY_SECONDS)
      count = cast_attempt(attempts)
      (1..count).sum do |n|
        delay_for(n, strategy: strategy, initial_delay: initial_delay,
                     max_delay: max_delay, jitter_percent: 0)
      end
    end

    def decorrelated(base, previous)
      low  = base
      high = [previous * 3.0, base].max
      low + ((high - low) * rand)
    end

    def apply_jitter(delay, jitter_percent)
      return delay if jitter_percent.zero?

      delay + (delay * (jitter_percent / 100.0) * rand)
    end

    def clamp(value, ceiling)
      [[value.to_f, 0.0].max, ceiling].min
    end

    def cast_attempt(value)
      n = Integer(value, exception: false)
      raise Error, "attempt must be a positive integer" unless n&.positive?
      raise Error, "attempt exceeds maximum of #{MAX_ATTEMPTS}" if n > MAX_ATTEMPTS

      n
    end

    def cast_strategy(value)
      strategy = value.to_s
      raise Error, "unsupported backoff strategy: #{value}" unless STRATEGIES.include?(strategy)

      strategy
    end

    def cast_seconds(value, label)
      seconds = Float(value, exception: false)
      raise Error, "#{label} must be a non-negative number" unless seconds && !seconds.negative?
      raise Error, "#{label} exceeds maximum of #{MAX_DELAY_SECONDS}" if seconds > MAX_DELAY_SECONDS

      seconds
    end

    def cast_percent(value)
      percent = Integer(value, exception: false)
      raise Error, "jitter_percent must be an integer" if percent.nil?
      raise Error, "jitter_percent must be between 0 and 100" if percent.negative? || percent > 100

      percent
    end
  end
end
