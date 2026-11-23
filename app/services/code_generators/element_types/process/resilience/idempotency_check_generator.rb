# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Resilience
        class IdempotencyCheckGenerator < BaseGenerator
          KEY_STRATEGIES = %w[ctx_field hash_of_inputs explicit].freeze
          ON_DUPLICATE = %w[fail skip flag].freeze
          SCOPES = FlowchartRuntime::Idempotency::SCOPES
          MIN_TTL_SECONDS = 1
          MAX_TTL_SECONDS = 86_400 * 30

          generator_metadata do
            description "Claims a tenant-scoped Rails.cache key so a double click cannot create two orders. Use rate_limiter to cap volume, not to dedupe one payload. keyStrategy 'ctx_field' (default) uses ctxField.to_s; 'hash_of_inputs' SHA-256-digests ctx[:params]; 'explicit' uses a Liquid explicitKey such as 'order:{{ model.id }}'. scope 'tenant' is unique per customer; 'user' also requires current_user_id. onDuplicate 'fail' (default) fails with duplicate_request; 'skip' continues; 'flag' continues and writes :claimed or :duplicate. ttlSeconds (default 3600) is how long the claim lasts. Fails with idempotency_check.failed on a blank key, and with idempotency_user_required when unsigned."
            category :resilience
            version "3.2.0"
            presentation icon: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
                        color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            enum :keyStrategy, KEY_STRATEGIES, default: "ctx_field",
              description: "'ctx_field' (default) uses ctxField. 'hash_of_inputs' digests ctx[:params]. 'explicit' uses the Liquid explicitKey."
            input :ctxField, example: "order_id", visible: { keyStrategy: "ctx_field" },
              description: "ctx path whose string value is the idempotency key, e.g. 'params.idempotency_key' or 'order_id'."
            template :explicitKey, example: "order:{{ model.id }}", max_length: 200, visible: { keyStrategy: "explicit" },
              description: "Liquid idempotency key, e.g. 'order:{{ model.id }}'. Shown when keyStrategy is 'explicit'."
            enum :scope, SCOPES, default: "tenant",
              description: "'tenant' (default) is unique per customer. 'user' is unique per signed-in current_user_id and fails when unsigned."
            enum :onDuplicate, ON_DUPLICATE, default: "fail",
              description: "'fail' (default) stops a duplicate with duplicate_request. 'skip' continues. 'flag' continues and writes :claimed or :duplicate to resultVar."
            integer :ttlSeconds, min: MIN_TTL_SECONDS, max: MAX_TTL_SECONDS, default: 3600,
              description: "Seconds the claimed key stays reserved (1-2592000). Default 3600. A later submit with the same key is a duplicate until then."
            output :resultVar, default: "idempotency_result",
              description: "ctx variable that receives :claimed or :duplicate. Default 'idempotency_result'."
            requires :ctxField, when: { keyStrategy: "ctx_field" }
            requires :explicitKey, when: { keyStrategy: "explicit" }
          end

          def generate_body
            claimed = "claimed = FlowchartRuntime::Idempotency.claim(ctx, #{key_source}#{claim_options})"
            stored = assign(:resultVar, "claimed")
            guard = value(:scope) == "user" ? "return false unless claimed" : nil
            inner = case value(:onDuplicate)
                    when "skip"
                      [claimed, stored, guard, "true"]
                    when "flag"
                      [claimed, stored, guard, "claimed"]
                    else
                      [claimed, stored, guard, fail_with(:duplicate_request, unless: "claimed == :claimed"), "claimed"]
                    end

            body(
              attempt(
                '"idempotency_check.failed"',
                FlowchartRuntime::Idempotency::Error,
                FlowchartRuntime::CacheKey::Error,
                FlowchartRuntime::Template::Error
              ) { inner }
            )
          end

          private

          def claim_options
            parts = ["ttl: #{read(:ttlSeconds)}"]
            parts << "scope: #{read(:scope)}" unless value(:scope) == "tenant"
            ", #{parts.join(', ')}"
          end

          def key_source
            case value(:keyStrategy)
            when "hash_of_inputs"
              "FlowchartRuntime::Idempotency.digest_inputs(ctx[:params])"
            when "explicit"
              read(:explicitKey)
            else
              "#{read(:ctxField)}.to_s"
            end
          end
        end
      end
    end
  end
end
