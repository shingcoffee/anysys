# frozen_string_literal: true

module FlowchartRuntime
  # Race-free tag index for flowchart cache entries.
  #
  # The previous implementation read a "<tag>:keys" array, appended to it and
  # wrote it back. Two concurrent writers both read the same array and the
  # second write silently dropped the first writer's key, so a later
  # invalidate-by-tag left stale entries behind.
  #
  # This implementation never reads-modifies-writes. Membership is encoded in
  # the *key* of an independent marker entry, so concurrent writers touch
  # disjoint keys and no update can be lost. Invalidation enumerates the marker
  # keys through FlowchartRuntime::CacheScope and derives the member cache keys
  # from the marker suffix.
  module CacheTags
    class Error < StandardError; end

    MARKER_SEGMENT = "__tag"

    module_function

    # Marks +scoped_key+ (a key already produced by CacheKey.scoped) as a member
    # of each tag. Idempotent and safe under concurrency.
    def tag(tenant_namespace, scoped_key, tags, expires_in: nil)
      names = normalize_tags(tags)
      return 0 if names.empty?

      key = scoped_key.to_s
      raise Error, "cache key is required" if key.empty?

      options = expires_in.to_i.positive? ? { expires_in: expires_in.to_i.seconds } : {}
      names.each { |name| Rails.cache.write(marker_key(tenant_namespace, name, key), true, **options) }
      names.size
    end

    # Deletes every cache entry tagged with +tag_name+ for this tenant, plus the
    # marker entries themselves.
    #
    # @return [Integer] number of member cache entries deleted
    def invalidate(tenant_namespace, tag_name)
      name = normalize_tag(tag_name)
      raise Error, "tag is required" if name.nil?

      prefix = marker_prefix(tenant_namespace, name)
      markers = CacheScope.matching_keys(tenant_namespace, "#{MARKER_SEGMENT}:#{name}:*")

      deleted = 0
      markers.each do |marker|
        member = marker.delete_prefix(prefix)
        next if member.empty?

        Rails.cache.delete(member)
        Rails.cache.delete(marker)
        deleted += 1
      end
      deleted
    end

    def marker_prefix(tenant_namespace, tag_name)
      "#{CacheScope.tenant_prefix(tenant_namespace)}#{MARKER_SEGMENT}:#{tag_name}:"
    end

    def marker_key(tenant_namespace, tag_name, scoped_key)
      "#{marker_prefix(tenant_namespace, tag_name)}#{scoped_key}"
    end

    # CacheScope globs are expressed relative to the tenant prefix.
    def normalize_tags(tags)
      Array(tags).filter_map { |tag| normalize_tag(tag) }.uniq
    end

    # Glob metacharacters are stripped so a tag name can never widen the
    # invalidation pattern beyond its own marker namespace.
    def normalize_tag(tag)
      value = case tag
              when Hash then tag["key"] || tag[:key] || tag["value"] || tag[:value]
              else tag
              end
      value = value.to_s.strip.delete("*?")
      value.empty? ? nil : value
    end

    private_class_method :normalize_tags, :normalize_tag
  end
end
