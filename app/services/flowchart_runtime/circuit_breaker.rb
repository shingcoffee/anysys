# frozen_string_literal: true

module FlowchartRuntime
  # Cache-backed circuit breaker for flowchart `circuit_breaker` steps.
  #
  # A flowchart step action cannot wrap the steps that follow it, so the
  # breaker is modelled as a *gate*: each execution reports the outcome of the
  # work that preceded it (`:success` / `:failure` / `:none`) and receives back
  # whether the protected call is allowed to proceed.
  #
  #   closed    → traffic flows; failures inside the rolling window are counted
  #   open      → traffic is refused until reset_timeout has elapsed
  #   half_open → a bounded number of trial requests is admitted;
  #               success_threshold consecutive successes close the circuit,
  #               a single failure re-opens it
  #
  # Every numeric parameter is validated and bounded here, so a flowchart
  # configuration can never produce an unbounded window or timeout. State is
  # namespaced per tenant through FlowchartRuntime::CacheKey.
  #
  # The read-modify-write cycle is not atomic across processes; the breaker is
  # deliberately advisory (a few extra trial requests during a race are
  # acceptable) rather than a distributed consensus device.
  module CircuitBreaker
    class Error < StandardError; end

    NAMESPACE          = "circuit_breaker"
    OUTCOMES           = %w[success failure none].freeze
    STATES             = %w[closed open half_open].freeze
    MAX_THRESHOLD      = 1_000
    MAX_TRIALS         = 100
    MAX_TIMEOUT_SECONDS = 86_400
    MAX_WINDOW_SECONDS  = 86_400
    JITTER_FRACTION     = 0.25

    module_function

    # @return [Hash] { state:, allowed:, failures:, successes:, retry_after: }
    def evaluate(tenant_namespace, name, outcome: "none", failure_threshold: 5,
                 success_threshold: 2, half_open_trials: 1, reset_timeout: 60,
                 window_size: 60, jitter: false)
      key       = cache_key(tenant_namespace, name)
      result    = cast_outcome(outcome)
      failures  = cast_bounded(failure_threshold, "failure_threshold", MAX_THRESHOLD)
      successes = cast_bounded(success_threshold, "success_threshold", MAX_THRESHOLD)
      trials    = cast_bounded(half_open_trials, "half_open_trials", MAX_TRIALS)
      timeout   = cast_bounded(reset_timeout, "reset_timeout", MAX_TIMEOUT_SECONDS)
      window    = cast_bounded(window_size, "window_size", MAX_WINDOW_SECONDS)

      now   = Time.current.to_f
      state = prune(read_state(key), now, window)
      state = record_outcome(state, result, now, failures, successes)
      state, allowed, retry_after = admit(state, now, timeout, trials, jitter)

      write_state(key, state, window, timeout)

      {
        state: state[:state],
        allowed: allowed,
        failures: state[:failures].size,
        successes: state[:successes],
        retry_after: retry_after
      }
    end

    # Drops all recorded state for a breaker (used by specs and manual resets).
    def reset(tenant_namespace, name)
      Rails.cache.delete(cache_key(tenant_namespace, name))
      true
    end

    def cache_key(tenant_namespace, name)
      breaker = name.to_s.strip
      raise Error, "breaker name is required" if breaker.empty?

      CacheKey.scoped(tenant_namespace, "breaker", breaker)
    rescue CacheKey::Error => e
      raise Error, e.message
    end

    def read_state(key)
      stored = Rails.cache.read(key)
      return blank_state unless stored.is_a?(Hash)

      {
        state: STATES.include?(stored[:state].to_s) ? stored[:state].to_s : "closed",
        failures: Array(stored[:failures]).map(&:to_f),
        successes: stored[:successes].to_i,
        trials: stored[:trials].to_i,
        opened_at: stored[:opened_at]&.to_f
      }
    end

    def write_state(key, state, window, timeout)
      Rails.cache.write(key, state, expires_in: ([window, timeout].max * 2).seconds)
    end

    def blank_state
      { state: "closed", failures: [], successes: 0, trials: 0, opened_at: nil }
    end

    def prune(state, now, window)
      state.merge(failures: state[:failures].select { |ts| ts > now - window })
    end

    def record_outcome(state, outcome, now, failure_threshold, success_threshold)
      case outcome
      when "failure" then record_failure(state, now, failure_threshold)
      when "success" then record_success(state, success_threshold)
      else state
      end
    end

    def record_failure(state, now, failure_threshold)
      failures = state[:failures] + [now]
      if state[:state] == "half_open" || failures.size >= failure_threshold
        state.merge(state: "open", failures: failures, successes: 0, trials: 0, opened_at: now)
      else
        state.merge(failures: failures)
      end
    end

    def record_success(state, success_threshold)
      return state.merge(successes: 0) unless state[:state] == "half_open"

      successes = state[:successes] + 1
      return state.merge(successes: successes) if successes < success_threshold

      blank_state
    end

    def admit(state, now, timeout, trials, jitter)
      case state[:state]
      when "open"      then admit_open(state, now, timeout, trials, jitter)
      when "half_open" then admit_half_open(state, trials)
      else [state, true, 0.0]
      end
    end

    def admit_open(state, now, timeout, trials, jitter)
      elapsed = now - (state[:opened_at] || now)
      wait    = effective_timeout(timeout, jitter)
      return [state, false, (wait - elapsed).round(3)] if elapsed < wait

      admit_half_open(state.merge(state: "half_open", successes: 0, trials: 0), trials)
    end

    def admit_half_open(state, trials)
      return [state, false, 0.0] if state[:trials] >= trials

      [state.merge(trials: state[:trials] + 1), true, 0.0]
    end

    # Jitter spreads the recovery probes of many workers that opened the same
    # breaker at the same instant, so they do not all retry in lockstep.
    def effective_timeout(timeout, jitter)
      return timeout.to_f unless jitter

      timeout + (timeout * JITTER_FRACTION * rand)
    end

    def cast_outcome(value)
      outcome = value.to_s
      raise Error, "unsupported outcome: #{value}" unless OUTCOMES.include?(outcome)

      outcome
    end

    def cast_bounded(value, label, maximum)
      number = Integer(value, exception: false)
      raise Error, "#{label} must be a positive integer" unless number&.positive?
      raise Error, "#{label} exceeds maximum of #{maximum}" if number > maximum

      number
    end
  end
end
