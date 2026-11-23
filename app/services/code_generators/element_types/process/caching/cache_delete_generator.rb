# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Caching
        class CacheDeleteGenerator < BaseGenerator
          # Pattern/namespace/all/tagged go through CacheScope, which enumerates
          # Solid Cache by SQL (Rails.cache.delete_matched is not supported there)
          # and always prefixes keys with this customer_id.
          SCOPES = %w[key pattern namespace all tagged].freeze
          MAX_PATTERN_KEYS = 10_000

          generator_metadata do
            description "Invalidates tenant-scoped flowchart cache entries for this customer only. Use cache_write or cache_fetch to populate keys and tags. scope 'key' deletes one Liquid cacheKey; 'pattern' deletes glob matches under this tenant (refuses at 10,000 keys when confirmPattern is true); 'namespace' deletes every key under the cacheKey prefix; 'all' clears this tenant's flowchart cache; 'tagged' invalidates the named tags. Bulk scopes enumerate via FlowchartRuntime::CacheScope (Solid Cache has no delete_matched) and cannot reach another tenant. Fails with cache_delete.failed on a bad key, a confirmation breach, or a missing tenant."
            category :caching
            version "3.2.0"
            presentation icon: "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16",
                          color: "red", single_use: false, privileged: false
          end

          config_schema do
            enum :scope, SCOPES, default: "key",
              description: "'key' deletes one cacheKey. 'pattern' globs under this tenant. 'namespace' deletes the cacheKey prefix. 'all' clears this tenant. 'tagged' invalidates tags."
            template :cacheKey, placeholder: true, example: "order_summary:{{ model.id }}",
              description: "For 'key', a Liquid key such as 'order_summary:{{ model.id }}'. For 'pattern', a glob like 'order:*'. For 'namespace', a prefix like 'order'."
            list :tags, item: :literal, default: [],
              description: "Tag names whose members are deleted when scope is 'tagged', matching tags set on cache_write."
            flag :confirmPattern, default: true, visible: { scope: "pattern" }, group: :advanced,
              description: "When true (default), refuse a pattern delete that matches 10,000 or more keys for this tenant."
            requires :cacheKey, when: { scope: "key" }
            requires :cacheKey, when: { scope: "pattern" }
            requires :cacheKey, when: { scope: "namespace" }
            requires :tags, when: { scope: "tagged" }
            validate do |cfg, errors|
              scope = cfg["scope"].to_s.presence || "key"
              CacheKeyGuard.validate(cfg, errors, :cacheKey) if scope == "key"
              errors.add(:tags, :required) if scope == "tagged" && Array(cfg["tags"]).empty?
            end
          end

          def generate_body
            body(
              attempt(
                '"cache_delete.failed"',
                FlowchartRuntime::CacheKey::Error,
                FlowchartRuntime::CacheScope::Error,
                FlowchartRuntime::CacheTags::Error,
                FlowchartRuntime::Template::Error
              ) { delete_lines + ["true"] }
            )
          end

          private

          def delete_lines
            case value(:scope)
            when "pattern"
              args = ["ctx[:customer_id]", read(:cacheKey)]
              args << "max_keys: #{MAX_PATTERN_KEYS}" if value(:confirmPattern)
              ["FlowchartRuntime::CacheScope.delete_matched(#{args.join(', ')})"]
            when "namespace"
              ["FlowchartRuntime::CacheScope.delete_matched(ctx[:customer_id], #{namespace_glob})"]
            when "all"
              ["FlowchartRuntime::CacheScope.clear(ctx[:customer_id])"]
            when "tagged"
              Array(value(:tags)).map(&:to_s).reject(&:empty?).uniq.map do |tag|
                "FlowchartRuntime::CacheTags.invalidate(ctx[:customer_id], #{literal(tag)})"
              end
            else
              ["Rails.cache.delete(FlowchartRuntime::CacheKey.scoped(ctx[:customer_id], #{read(:cacheKey)}))"]
            end
          end

          def namespace_glob
            "#{read(:cacheKey)} + \"*\""
          end
        end
      end
    end
  end
end
