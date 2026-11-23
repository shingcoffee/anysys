# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Resilience
        class RateLimiterGenerator < BaseGenerator
          ON_EXCEED = %w[fail skip].freeze
          SCOPES = FlowchartRuntime::RateLimiter::SCOPES
          MAX_CAPACITY = 100_000
          MAX_WINDOW = 86_400
          MAX_COST = 100

          generator_metadata do
            description "Throttles how often this customer (or user, IP, or custom value) may pass a step, using one atomic cache increment per run. Use idempotency_check to block a duplicate payload. limiterName is a stable label (e.g. 'signup'). capacity (default 100) slots per window seconds (default 60). scope 'global' is one bucket for the customer; 'user' uses current_user_id; 'ip' uses request_ip; 'custom' uses scopeVariable. cost (default 1) is consumed in one increment. onExceed 'fail' (default) fails with rate_limited; 'skip' continues. Writes allowed to resultVar and seconds until reset to retryAfterVar. Fails with rate_limiter.failed on a blank name, bad scope, or missing tenant."
            category :resilience
            version "3.2.0"
            presentation icon: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
                        color: "amber", single_use: false, privileged: false
          end

          config_schema do
            literal :limiterName, required: true, example: "api_calls", max_length: 100,
              description: "Stable label for this limiter, e.g. 'signup' or 'checkout'. Tenant-scoped; wildcards are refused."
            integer :capacity, min: 1, max: MAX_CAPACITY, default: 100,
              description: "How many slots the current window admits (1-100000). Default 100."
            integer :window, min: 1, max: MAX_WINDOW, default: 60,
              description: "Window length in seconds (1-86400). Default 60. The count resets when the next window starts."
            enum :scope, SCOPES, default: "global",
              description: "'global' (default) is one bucket for the customer. 'user' uses current_user_id. 'ip' uses request_ip. 'custom' uses scopeVariable."
            input :scopeVariable, example: "order_id", visible: { scope: "custom" },
              description: "ctx path whose string value further scopes the bucket when scope is 'custom', e.g. 'account_id'."
            integer :cost, min: 1, max: MAX_COST, default: 1,
              description: "Slots this run consumes in one atomic increment (1-100). Default 1. Use a higher cost for expensive work."
            enum :onExceed, ON_EXCEED, default: "fail",
              description: "'fail' (default) fails with rate_limited when the window is full. 'skip' continues. The step never waits."
            output :resultVar, default: "throttle_state",
              description: "ctx variable set to true when the run is admitted, false when denied. Default 'throttle_state'."
            output :retryAfterVar, default: "retry_after_seconds", group: :advanced,
              description: "ctx variable set to seconds until the window resets when denied, or 0 when admitted. Default 'retry_after_seconds'."
            requires :scopeVariable, when: { scope: "custom" }
            validate do |cfg, errors|
              name = cfg["limiterName"].to_s
              next if name.empty?
              next unless name.match?(/[*?]/)

              errors.add(:limiterName, :invalid_identifier)
            end
          end

          def generate_body
            decision = "decision = FlowchartRuntime::RateLimiter.check(ctx, #{read(:limiterName)}, #{check_args})"
            allowed = assign(:resultVar, "decision[:allowed]")
            retry_after = assign(:retryAfterVar, "decision[:retry_after]")
            inner = if value(:onExceed) == "skip"
              [decision, allowed, retry_after, "true"]
            else
              [decision, allowed, retry_after, fail_with(:rate_limited, unless: "decision[:allowed]"), "true"]
            end

            body(
              attempt(
                '"rate_limiter.failed"',
                FlowchartRuntime::RateLimiter::Error,
                FlowchartRuntime::CacheKey::Error
              ) { inner }
            )
          end

          private

          def check_args
            parts = [
              "capacity: #{read(:capacity)}",
              "window: #{read(:window)}"
            ]
            parts << "scope: #{read(:scope)}" unless value(:scope) == "global"
            parts << "cost: #{read(:cost)}" unless value(:cost) == 1
            parts << "scope_value: #{read(:scopeVariable)}" if value(:scope) == "custom"
            parts.join(", ")
          end
        end
      end
    end
  end
end
