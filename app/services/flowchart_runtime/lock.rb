# frozen_string_literal: true

module FlowchartRuntime
  # Cache-backed distributed mutex for flowchart acquire_lock / release_lock
  # and Entries.upsert. Never waits: one write with unless_exist.
  module Lock
    class Error < StandardError; end

    MAX_TTL_SECONDS = 3600

    module_function

    def acquire(tenant_namespace, key, token, ttl:)
      validate_identity!(tenant_namespace, key, token)
      ttl_seconds = Integer(ttl, exception: false)
      raise Error, "ttl must be positive" unless ttl_seconds&.positive?
      raise Error, "ttl exceeds maximum of #{MAX_TTL_SECONDS}" if ttl_seconds > MAX_TTL_SECONDS

      Rails.cache.write(cache_key(tenant_namespace, key), token, expires_in: ttl_seconds.seconds, unless_exist: true)
    rescue CacheKey::Error, ActiveRecord::ActiveRecordError => e
      raise Error, e.message
    end

    def release(tenant_namespace, key, token)
      validate_identity!(tenant_namespace, key, token)
      atomic_compare_and_delete(Rails.cache, cache_key(tenant_namespace, key), token)
    rescue CacheKey::Error, ActiveRecord::ActiveRecordError => e
      raise Error, e.message
    end

    def cache_key(tenant_namespace, key)
      CacheKey.scoped(tenant_namespace, "lock", key)
    end

    def validate_identity!(tenant_namespace, key, token)
      raise Error, "tenant namespace is required" if tenant_namespace.to_s.empty?
      raise Error, "key is required" if key.to_s.empty?
      raise Error, "token is required" if token.to_s.empty?
    end

    def atomic_compare_and_delete(cache, key, token)
      return cache.compare_and_delete(key, token) if cache.respond_to?(:compare_and_delete)
      return memory_store_compare_and_delete(cache, key, token) if cache.is_a?(ActiveSupport::Cache::MemoryStore)
      return solid_cache_compare_and_delete(cache, key, token) if cache.is_a?(SolidCache::Store)

      raise Error, "cache store does not support atomic compare-and-delete"
    end

    def solid_cache_compare_and_delete(cache, key, token)
      options = cache.send(:merged_options, nil)
      normalized_key = cache.send(:normalize_key, key, options)
      released = false

      cache.send(:entry_lock_and_write, normalized_key) do |payload|
        entry = cache.send(:deserialize_entry, payload)
        if entry && !entry.expired? && entry.value == token
          SolidCache::Entry.delete_by_key(normalized_key)
          released = true
        end
        nil
      end

      released
    end

    def memory_store_compare_and_delete(cache, key, token)
      monitor = cache.instance_variable_get(:@monitor)
      monitor.synchronize do
        return false unless cache.read(key) == token

        cache.delete(key)
      end
    end
    private_class_method :validate_identity!, :atomic_compare_and_delete,
      :solid_cache_compare_and_delete, :memory_store_compare_and_delete
  end
end
