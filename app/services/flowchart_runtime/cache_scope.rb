# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped bulk operations over the flowchart cache namespace.
  #
  # Every flowchart cache entry is written under the prefix produced by
  # FlowchartRuntime::CacheKey.scoped, i.e. "flowchart:cache:<tenant>:...".
  # This facade is the single entry point for anything that touches *more than
  # one* key at a time, so a pattern or "clear everything" step can never reach
  # another customer's entries (Rails.cache.clear would).
  module CacheScope
    class Error < StandardError; end

    # Refuse a destructive pattern delete above this many keys when the step
    # asked for a confirmed delete.
    DEFAULT_MAX_KEYS = 10_000

    module_function

    def tenant_prefix(tenant_namespace)
      tenant = tenant_namespace.to_s.strip
      raise Error, "tenant namespace is required" if tenant.empty?

      "#{CacheKey::CACHE_PREFIX}#{tenant}:"
    end

    # Keys belonging to +tenant_namespace+ whose unscoped portion matches +glob+.
    def matching_keys(tenant_namespace, glob)
      prefix = tenant_prefix(tenant_namespace)
      matcher = glob_to_regexp("#{prefix}#{glob}")
      enumerate(prefix).select { |key| matcher.match?(key) }
    end

    def count_matching(tenant_namespace, glob)
      matching_keys(tenant_namespace, glob).size
    end

    # Deletes every tenant-scoped key matching +glob+.
    #
    # When +max_keys+ is given the delete is *confirmed*: the matching set is
    # counted first and the operation is refused when it is at or above the
    # limit. Confirmation therefore requires an enumerable store.
    #
    # @return [Integer, nil] number of deleted keys, or nil when the store could
    #   only perform an unconfirmed delete_matched.
    def delete_matched(tenant_namespace, glob, max_keys: nil)
      prefix = tenant_prefix(tenant_namespace)

      unless enumerable?
        raise Error, "cache store #{Rails.cache.class} cannot count keys; confirmation is unavailable" if max_keys
        raise Error, "cache store #{Rails.cache.class} cannot delete by pattern" unless Rails.cache.respond_to?(:delete_matched)

        Rails.cache.delete_matched(glob_to_regexp("#{prefix}#{glob}"))
        return nil
      end

      keys = matching_keys(tenant_namespace, glob)
      if max_keys && keys.size >= max_keys.to_i
        raise Error, "pattern matches #{keys.size} keys, at or above the confirmed limit of #{max_keys}"
      end

      delete_all(keys)
    end

    # Deletes every flowchart cache entry belonging to this tenant only.
    def clear(tenant_namespace)
      prefix = tenant_prefix(tenant_namespace)
      raise Error, "cache store #{Rails.cache.class} cannot enumerate keys" unless enumerable?

      delete_all(enumerate(prefix))
    end

    def delete_all(keys)
      keys.each { |key| Rails.cache.delete(key) }
      keys.size
    end

    def glob_to_regexp(glob)
      escaped = Regexp.escape(glob.to_s).gsub('\\*', ".*").gsub('\\?', ".")
      /\A#{escaped}\z/
    end

    def enumerable?
      cache = Rails.cache
      return true if cache.is_a?(ActiveSupport::Cache::NullStore)
      return true if cache.is_a?(ActiveSupport::Cache::MemoryStore)
      return true if cache.is_a?(SolidCache::Store)

      false
    end

    def enumerate(prefix)
      cache = Rails.cache
      return [] if cache.is_a?(ActiveSupport::Cache::NullStore)

      if cache.is_a?(ActiveSupport::Cache::MemoryStore)
        monitor = cache.instance_variable_get(:@monitor)
        data = cache.instance_variable_get(:@data)
        keys = monitor ? monitor.synchronize { data.keys.dup } : data.keys.dup
        return keys.map(&:to_s).select { |key| key.start_with?(prefix) }
      end

      if cache.is_a?(SolidCache::Store)
        return SolidCache::Entry.where("key LIKE ?", "#{sanitize_like(prefix)}%").pluck(:key).map { |key| key.to_s }
      end

      raise Error, "cache store #{cache.class} cannot enumerate keys"
    end

    def sanitize_like(value)
      value.to_s.gsub(/[%_]/) { |char| "\\#{char}" }
    end

    private_class_method :delete_all, :enumerate, :sanitize_like
  end
end
