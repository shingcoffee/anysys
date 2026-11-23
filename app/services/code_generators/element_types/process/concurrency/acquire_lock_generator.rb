# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Concurrency
        class AcquireLockGenerator < BaseGenerator
          ON_CONFLICT = %w[fail skip].freeze
          SAFE_CTX_RE = /\Actx\[:([A-Za-z_][A-Za-z0-9_]*)\]\z/
          SAFE_SHORTHAND_RE = /\Actx:([A-Za-z_][A-Za-z0-9_]*)\z/

          generator_metadata do
            description "Acquires a tenant-scoped Rails.cache lock without waiting, so two submits cannot process the same order at once. Pair with release_lock: this step stores the lock name in lockKeyVar (default _cache_lock_key) and the holder token in tokenVar (default _lock_token). lockKey is a Liquid template such as 'order:{{ model.id }}', or lockKeyVariable a ctx path. ttl (default 30s, max 3600) is how long the lock lives if a later step fails before release_lock runs — put release_lock on the failure track to release early. onConflict 'fail' (default) fails with acquire_lock.lock_busy; 'skip' continues without the lock. Fails with acquire_lock.failed on a blank key or missing tenant."
            category :concurrency
            version "5.0.0"
            presentation icon: "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            template :lockKey, example: "order:{{ model.id }}", placeholder: true,
              description: "Liquid lock name, e.g. 'order:{{ model.id }}'. Use lockKeyVariable instead to read the name from ctx. One of the two is required."
            input :lockKeyVariable,
              description: "ctx path holding the lock name, e.g. 'job_id'. When set, it wins over lockKey."
            literal :holderIdentity, placeholder: true,
              description: "Holder token written to the lock. Blank generates SecureRandom.hex. A ctx[:name] path is also accepted."
            integer :ttl, min: 1, max: FlowchartRuntime::Lock::MAX_TTL_SECONDS, default: 30,
              description: "Seconds the lock is held if release_lock never runs (1-3600, default 30). The lock then expires on its own."
            enum :onConflict, ON_CONFLICT, default: "fail",
              description: "'fail' (default) fails the step with acquire_lock.lock_busy. 'skip' continues without holding the lock. The step never waits."
            output :lockKeyVar, default: "_cache_lock_key",
              description: "ctx variable that stores the lock name for release_lock. Default '_cache_lock_key'."
            output :tokenVar, default: "_lock_token",
              description: "ctx variable that stores the holder token for release_lock. Default '_lock_token'."
            validate do |cfg, errors|
              if cfg["lockKey"].to_s.strip.empty? && cfg["lockKeyVariable"].to_s.strip.empty?
                errors.add(:lockKey, :required)
              end
              holder = cfg["holderIdentity"].to_s
              if holder.include?("\n") || (holder.start_with?("ctx[") && !SAFE_CTX_RE.match?(holder))
                errors.add(:holderIdentity, :invalid_holder)
              end
            end
          end

          def generate_body
            conflict = value(:onConflict)
            fail_line = if conflict == "skip"
              "return true unless acquired"
            else
              fail_with('"acquire_lock.lock_busy"', unless: "acquired")
            end

            body(
              attempt(
                '"acquire_lock.failed"',
                FlowchartRuntime::Lock::Error,
                FlowchartRuntime::Template::Error
              ) do
                [
                  "lock_key = #{lock_key_expr}",
                  "lock_token = #{holder_expr}",
                  "acquired = FlowchartRuntime::Lock.acquire(ctx[:customer_id], lock_key, lock_token, ttl: #{read(:ttl)})",
                  fail_line,
                  assign(:lockKeyVar, "lock_key"),
                  assign(:tokenVar, "lock_token"),
                  "true"
                ]
              end
            )
          end

          private

          def lock_key_expr
            return "#{read(:lockKeyVariable)}.to_s" if value(:lockKeyVariable).to_s.strip.present?

            read(:lockKey)
          end

          def holder_expr
            raw = value(:holderIdentity).to_s.strip
            return "SecureRandom.hex" if raw.empty?
            return "ctx[:#{Regexp.last_match(1)}]" if raw.match(SAFE_CTX_RE) || raw.match(SAFE_SHORTHAND_RE)

            read(:holderIdentity)
          end
        end
      end
    end
  end
end
