# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        class CacheReadGenerator < BaseGenerator
          ON_MISS = %w[nil default].freeze

          generator_metadata do
            description "Reads one tenant-scoped Rails.cache value into ctx. Prefer cache_fetch when a miss should compute and store a fallback, cache_write to store a known value, and cache_delete to invalidate. cacheKey is a Liquid template such as 'order_summary:{{ model.id }}' and is always prefixed with this customer_id. Writes the entry to resultVar (default 'cached'). onMiss 'nil' leaves a miss as nil; 'default' assigns defaultValue. The step still succeeds on a miss. Fails with cache_read.failed when the tenant is missing or the key is blank or contains a wildcard."
            category :caching
            version "3.2.0"
            presentation icon: "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4",
                          color: "cyan", single_use: false, privileged: false
          end

          config_schema do
            template :cacheKey, required: true, example: "order_summary:{{ model.id }}", placeholder: true,
              description: "Liquid template for the tenant-scoped key, e.g. 'order_summary:{{ model.id }}'. Static text is fine. Wildcards are refused."
            output :resultVar, default: "cached",
              description: "ctx variable that receives the cached value or the on-miss default. Default 'cached'."
            literal :namespace, placeholder: true, group: :advanced,
              description: "Optional literal prefix inserted before the key, e.g. 'reports'. Leave blank for none."
            literal :versionCheck, placeholder: true, group: :advanced,
              description: "Optional version token such as 'v2', or a ctx[:name] path. A changed version misses the old entry."
            enum :onMiss, ON_MISS, default: "nil",
              description: "'nil' (default) leaves resultVar nil on a miss and still succeeds. 'default' assigns defaultValue instead."
            expression :defaultValue, placeholder: true, example: "{}",
              description: "Ruby expression assigned when onMiss is 'default' and the key is absent, such as {}, 0 or ctx[:fallback]."
            requires :defaultValue, when: { onMiss: "default" }
            validate { |cfg, errors| CacheKeyGuard.validate(cfg, errors, :cacheKey, :namespace) }
          end

          def generate_body
            lines = [
              "cache_key = #{scoped_key}",
              assign(:resultVar, "Rails.cache.read(cache_key#{read_options})")
            ]
            if value(:onMiss) == "default"
              lines << "ctx[:#{value(:resultVar)}] ||= #{read(:defaultValue)}"
            end
            lines << "true"

            body(
              attempt(
                '"cache_read.failed"',
                FlowchartRuntime::CacheKey::Error,
                FlowchartRuntime::Template::Error
              ) { lines }
            )
          end

          private

          def scoped_key
            args = ["ctx[:customer_id]", read(:cacheKey)]
            args << "namespace: #{read(:namespace)}" if value(:namespace).to_s.strip.present?
            "FlowchartRuntime::CacheKey.scoped(#{args.join(', ')})"
          end

          def read_options
            ", version: #{version_source}" if value(:versionCheck).to_s.strip.present?
          end

          def version_source
            raw = value(:versionCheck).to_s.strip
            if (match = raw.match(/\Actx\[:([A-Za-z_][A-Za-z0-9_]*)\]\z/))
              "ctx[:#{match[1]}]"
            else
              read(:versionCheck)
            end
          end
        end
      end
    end
  end
end
