# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        class CacheFetchGenerator < BaseGenerator
          generator_metadata do
            description "Read-through cache: return a tenant-scoped Rails.cache hit, or compute fallbackExpression, store it, and return it. Use cache_read to look up without computing, cache_write to store an already-known value, and cache_delete to invalidate. cacheKey is a Liquid template such as 'order_summary:{{ model.id }}'. Writes the value to resultVar. Optional ttl, namespace, versionKey, raceConditionTtl, forceRefresh (ignore a hit), and skipNilCache (default true, do not store nil). Fails with cache_fetch.failed when the tenant is missing or the key is blank or contains a wildcard."
            category :caching
            version "2.2.0"
            presentation icon: "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15",
                          color: "blue", single_use: false, privileged: false
          end

          config_schema do
            template :cacheKey, required: true, example: "order_summary:{{ model.id }}", placeholder: true,
              description: "Liquid template for the tenant-scoped key, e.g. 'order_summary:{{ model.id }}'. Static text is fine. Wildcards are refused."
            input :fallbackExpression, required: true, example: "order_total",
              description: "ctx path computed on a miss and then stored, e.g. 'order_total'. Must be a ctx identifier, not Ruby."
            output :resultVar, default: "cached",
              description: "ctx variable that receives the hit or the computed fallback. Default 'cached'."
            integer :ttl, min: 1, max: 86_400,
              description: "Seconds until the stored value expires (1-86400). Blank keeps it until cache_delete or eviction."
            integer :raceConditionTtl, min: 1, max: 3600, group: :advanced,
              description: "Extra seconds Rails.cache keeps a stale value during a stampede (1-3600). Leave blank to disable."
            flag :forceRefresh, default: false, group: :advanced,
              description: "When true, ignore a cached hit and recompute fallbackExpression. Default false."
            flag :skipNilCache, default: true, group: :advanced,
              description: "When true (default), a nil fallback is returned but not stored, so the next run recomputes."
            literal :namespace, placeholder: true, group: :advanced,
              description: "Optional literal prefix inserted before the key, e.g. 'reports'. Leave blank for none."
            literal :versionKey, placeholder: true, group: :advanced,
              description: "Optional version token such as 'v2'. A changed version misses the old entry."
            validate { |cfg, errors| CacheKeyGuard.validate(cfg, errors, :cacheKey, :namespace) }
          end

          def generate_body
            body(
              attempt(
                '"cache_fetch.failed"',
                FlowchartRuntime::CacheKey::Error,
                FlowchartRuntime::Template::Error
              ) do
                [
                  "cache_key = #{scoped_key}",
                  assign(:resultVar, "Rails.cache.fetch(cache_key#{fetch_options}) { #{read(:fallbackExpression)} }"),
                  "true"
                ]
              end
            )
          end

          private

          def scoped_key
            args = ["ctx[:customer_id]", read(:cacheKey)]
            args << "namespace: #{read(:namespace)}" if value(:namespace).to_s.strip.present?
            "FlowchartRuntime::CacheKey.scoped(#{args.join(', ')})"
          end

          def fetch_options
            parts = []
            parts << "expires_in: #{read(:ttl)}" if value(:ttl).to_i.positive?
            parts << "race_condition_ttl: #{read(:raceConditionTtl)}" if value(:raceConditionTtl).to_i.positive?
            parts << "force: true" if value(:forceRefresh)
            parts << "skip_nil: true" if value(:skipNilCache)
            parts << "version: #{read(:versionKey)}" if value(:versionKey).to_s.strip.present?
            parts.empty? ? "" : ", #{parts.join(', ')}"
          end
        end
      end
    end
  end
end
