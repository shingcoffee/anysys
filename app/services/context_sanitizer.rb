# frozen_string_literal: true

class ContextSanitizer
  include Loggable

  class << self
    def sanitize(ctx)
      new(ctx).sanitize
    end
  end

  def initialize(ctx)
    @ctx = ctx
  end

  def sanitize
    transform_values(@ctx)
  rescue StandardError => e
    log_warn "#{e.class} - #{e.message}"
    @ctx.to_s
  end

  private

  def transform_values(hash)
    hash.each_with_object(hash.class.new) do |(key, value), out|
      next if internal_key?(key)

      out[key] = serialize_value(value)
    end
  end

  def internal_key?(key)
    key.to_s.start_with?("_")
  end

  def serialize_value(value)
    case value
    when String, Numeric, TrueClass, FalseClass, NilClass
      value
    when Hash
      transform_values(value)
    when Array
      value.map { |item| item.is_a?(Hash) ? transform_values(item) : item.inspect }
    else
      value.inspect
    end
  end
end
