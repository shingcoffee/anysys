# frozen_string_literal: true

module FlowchartRuntime
  # ContextResolver
  #
  # Resolves dynamic value references in flowchart step configurations at runtime.
  # Inspired by CiviCore's variable interpolation system.
  #
  # Supported value forms:
  #   - "ctx.field"            → ctx[:field]
  #   - "ctx.record.name"      → ctx[:record][:name]  (nested dig)
  #   - "ctx.items.0.name"     → ctx[:items][0][:name] (array index support)
  #   - "Hello {{ctx.name}}"   → interpolated string
  #   - "$true"                → true
  #   - "$false"               → false
  #   - "$nil"                 → nil
  #   - "42" / "3.14"          → integer / float
  #   - Hash                   → recursively resolved hash
  #   - Array                  → recursively resolved array
  #   - anything else          → literal string value
  #
  # @example
  #   FlowchartRuntime::ContextResolver.resolve("ctx.status", { status: "approved" })
  #   # => "approved"
  #
  #   FlowchartRuntime::ContextResolver.resolve("Hello {{ctx.name}}", { name: "Alice" })
  #   # => "Hello Alice"
  #
  module ContextResolver
    class Error < StandardError; end

    CTX_PREFIX        = "ctx."
    TEMPLATE_PATTERN  = /\{\{(ctx\.[^}]+)\}\}/
    INTEGER_PATTERN   = /\A-?\d+\z/
    FLOAT_PATTERN     = /\A-?\d+\.\d+\z/

    module_function

    # Resolve a single value against the provided context hash.
    #
    # @param value [Object] the value to resolve
    # @param ctx   [Hash]   runtime context, symbol-keyed
    # @return [Object] resolved value
    def resolve(value, ctx)
      raise Error, "context must be a hash" unless ctx.is_a?(Hash)

      case value
      when nil, ""
        value
      when Hash
        value.transform_values { |v| resolve(v, ctx) }
      when Array
        value.map { |v| resolve(v, ctx) }
      when String
        resolve_string(value, ctx)
      else
        value
      end
    end

    # Resolve all values in a config hash against the provided context.
    #
    # @param config_hash [Hash] configuration hash whose values may contain references
    # @param ctx         [Hash] runtime context, symbol-keyed
    # @return [Hash] new hash with all values resolved
    def resolve_all(config_hash, ctx)
      return {} unless config_hash.is_a?(Hash)
      raise Error, "context must be a hash" unless ctx.is_a?(Hash)

      config_hash.transform_values { |v| resolve(v, ctx) }
    end

    private

    module_function

    def resolve_string(value, ctx)
      return resolve_ctx_path(value, ctx)  if value.start_with?(CTX_PREFIX)
      return true                           if value == "$true"
      return false                          if value == "$false"
      return nil                            if value == "$nil"
      return value.to_i                     if value.match?(INTEGER_PATTERN)
      return value.to_f                     if value.match?(FLOAT_PATTERN)
      return interpolate_template(value, ctx) if value.match?(TEMPLATE_PATTERN)

      value
    end

    # Resolve a "ctx.a.b.0.c" path against the context hash.
    # Integer-looking path segments are treated as array indices.
    def resolve_ctx_path(value, ctx)
      parts = value.sub(CTX_PREFIX, "").split(".")
      parts.reduce(ctx) do |current, part|
        break nil if current.nil?

        case current
        when Array
          raise Error, "cannot resolve #{value} through an array without an index" unless integer_string?(part)

          current[part.to_i]
        when Hash
          key = integer_string?(part) ? part.to_i : part.to_sym
          current[key]
        else
          raise Error, "cannot resolve #{value} through #{current.class}"
        end
      end
    end

    def interpolate_template(value, ctx)
      value.gsub(TEMPLATE_PATTERN) do |_match|
        path     = Regexp.last_match(1)
        resolved = resolve_ctx_path(path, ctx)
        resolved.nil? ? "" : resolved.to_s
      end
    end

    def integer_string?(str)
      str.match?(INTEGER_PATTERN)
    end
  end
end
