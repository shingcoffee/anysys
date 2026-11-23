# frozen_string_literal: true

module FlowchartRuntime
  # Builds tenant-scoped Rails.cache keys for flowchart runtime helpers.
  #
  # Existing generated steps still call `.scoped(tenant, key, namespace:, version:)`.
  # New helpers pass additional positional parts: `.scoped(tenant, "breaker", name)`.
  module CacheKey
    class Error < StandardError; end

    CACHE_PREFIX = "flowchart:"
    MAX_PART_BYTES = 200
    WILDCARD_RE = /[*?\[]/

    module_function

    def scoped(tenant_namespace, *parts, namespace: nil, version: nil)
      tenant = tenant_namespace.to_s.strip
      raise Error, "tenant namespace is required" if tenant.empty?

      tokens = []
      user_namespace = namespace.to_s.strip
      tokens << user_namespace unless user_namespace.empty?
      parts.each { |part| tokens << validated_part(part) }
      suffix = version.to_s.strip
      tokens << suffix unless suffix.empty?
      raise Error, "cache key is required" if tokens.empty?

      "#{CACHE_PREFIX}#{tenant}:#{tokens.join(':')}"
    end

    def validated_part(part)
      token = part.to_s
      raise Error, "cache key is required" if token.strip.empty?
      raise Error, "cache key contains a wildcard" if token.match?(WILDCARD_RE)
      raise Error, "cache key exceeds maximum length" if token.bytesize > MAX_PART_BYTES

      token
    end
    private_class_method :validated_part
  end
end
