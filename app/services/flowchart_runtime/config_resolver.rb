# frozen_string_literal: true

module FlowchartRuntime
  module ConfigResolver
    class Error < StandardError; end

    module_function

    def resolve(config, ctx)
      return {} if config.nil? || !config.is_a?(Hash)

      overrides = config["overrides"]
      base = config.except("overrides")

      return base if overrides.blank?
      raise Error, "context must be a hash" unless ctx.is_a?(Hash)

      result = base.deep_dup

      overrides.each do |override|
        next unless override.is_a?(Hash)
        next unless matches?(override["when"], ctx)

        apply = override["apply"]
        next unless apply.is_a?(Hash)

        # ActiveSupport's Hash#deep_merge: nested hashes merge, other values override.
        result = result.deep_merge(apply)
      end

      result
    rescue ContextResolver::Error => e
      raise Error, e.message
    end

    def matches?(when_clause, ctx)
      return false if when_clause.blank? || !when_clause.is_a?(Hash)

      when_clause.all? do |key, expected|
        case key
        when "role"
          ctx[:current_user_role].to_s == expected.to_s
        when "device"
          ctx[:device_type].to_s == expected.to_s
        when "condition"
          value = ContextResolver.resolve(expected, ctx)
          !!value
        else
          false
        end
      end
    end
  end
end
