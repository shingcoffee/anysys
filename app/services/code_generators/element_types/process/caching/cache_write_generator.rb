# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        class CacheWriteGenerator < BaseGenerator
          ACTIONS = %w[write write_if_absent].freeze

          generator_metadata do
            description "Stores a ctx value in the tenant-scoped Rails.cache. Use cache_fetch for read-through filling, cache_read to look up without writing, and cache_delete to invalidate. cacheKey is a Liquid template (e.g. 'order_summary:{{ model.id }}') scoped by customer_id. Reads sourceVariable and writes it under that key. action 'write' overwrites; 'write_if_absent' uses unless_exist so a populated key is left alone. Optional ttl (seconds), namespace, version, tags (for cache_delete tagged), and raceConditionTtl (stampede guard). Fails with cache_write.failed on a blank/wildcard key or missing tenant. The step succeeds even when write_if_absent skips."
            category :caching
            version "4.0.0"
            presentation icon: "M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4",
                          color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            template :cacheKey, required: true, example: "order_summary:{{ model.id }}", placeholder: true,
              description: "Liquid template for the tenant-scoped key, e.g. 'order_summary:{{ model.id }}'. Static text is fine. Wildcards are refused."
            enum :action, ACTIONS, default: "write",
              description: "'write' (default) overwrites the key. 'write_if_absent' stores only when the key is missing (unless_exist)."
            input :sourceVariable, default: "data",
              description: "ctx path holding the value to store, e.g. 'order' or 'totals.grand'. Default 'data'."
            integer :ttl, min: 1, max: 86_400,
              description: "Seconds until the entry expires (1-86400). Blank keeps the value until cache_delete or eviction."
            integer :raceConditionTtl, min: 1, max: 3600, group: :advanced,
              description: "Extra seconds Rails.cache keeps a stale value during a stampede (1-3600). Leave blank to disable."
            literal :namespace, placeholder: true, group: :advanced,
              description: "Optional literal prefix inserted before the key, e.g. 'reports'. Leave blank for none."
            literal :version, placeholder: true, group: :advanced,
              description: "Optional version token such as 'v2'. A changed version stores beside the old entry."
            list :tags, item: :literal, default: [], group: :advanced,
              description: "Tag names this key joins, e.g. 'order'. cache_delete with scope 'tagged' invalidates them together."
            validate { |cfg, errors| CacheKeyGuard.validate(cfg, errors, :cacheKey, :namespace) }
          end

          def generate_body
            lines = [
              "cache_key = #{scoped_key}",
              "Rails.cache.write(cache_key, #{read(:sourceVariable)}#{write_options})"
            ]
            names = Array(value(:tags)).map(&:to_s).reject(&:empty?).uniq
            unless names.empty?
              tag_args = ["ctx[:customer_id]", "cache_key", read(:tags)]
              tag_args << "expires_in: #{read(:ttl)}" if value(:ttl).to_i.positive?
              lines << "FlowchartRuntime::CacheTags.tag(#{tag_args.join(', ')})"
            end
            lines << "true"

            body(
              attempt(
                '"cache_write.failed"',
                FlowchartRuntime::CacheKey::Error,
                FlowchartRuntime::CacheTags::Error,
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

          def write_options
            parts = []
            parts << "expires_in: #{read(:ttl)}" if value(:ttl).to_i.positive?
            parts << "unless_exist: true" if value(:action) == "write_if_absent"
            parts << "race_condition_ttl: #{read(:raceConditionTtl)}" if value(:raceConditionTtl).to_i.positive?
            parts << "version: #{read(:version)}" if value(:version).to_s.strip.present?
            parts.empty? ? "" : ", #{parts.join(', ')}"
          end
        end
      end
    end
  end
end
