# frozen_string_literal: true

module FlowchartRuntime
  module Idempotency
    class Error < StandardError; end

    SCOPES = %w[tenant user].freeze

    module_function

    def digest_inputs(payload)
      Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(payload.as_json))
    end

    def claim(ctx, key, ttl:, scope: "tenant")
      token = key.to_s.strip
      raise Error, "key is required" if token.empty?

      seconds = Integer(ttl, exception: false)
      raise Error, "ttl must be positive" unless seconds&.positive?

      cache_key = cache_key_for(ctx, token, scope)
      return cache_key unless cache_key.is_a?(String)

      wrote = Rails.cache.write(
        cache_key,
        true,
        expires_in: seconds.seconds,
        unless_exist: true
      )
      wrote ? :claimed : :duplicate
    end

    def cache_key_for(ctx, token, scope)
      customer_id = ctx && ctx[:customer_id]
      case scope.to_s
      when "user"
        user_id = ctx && ctx[:current_user_id]
        return Step.fail(ctx, :idempotency_user_required) if user_id.blank?

        CacheKey.scoped(customer_id, "idempotency", "user", user_id, token)
      when "tenant", ""
        CacheKey.scoped(customer_id, "idempotency", token)
      else
        raise Error, "unknown scope"
      end
    end
    private_class_method :cache_key_for
  end
end
