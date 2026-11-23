# frozen_string_literal: true

module Sms
  class Result
    attr_reader :value, :errors, :code

    def initialize(success:, value: nil, errors: {}, code: nil)
      @success = success
      @value = self.class.immutable(value)
      @errors = self.class.immutable(errors.to_h.transform_keys(&:to_sym).transform_values { |messages| Array(messages) })
      @code = code&.to_sym
      freeze
    end

    def success? = @success
    def self.success(value) = new(success: true, value: value)
    def self.failure(code, errors: {}) = new(success: false, code: code, errors: errors)

    def self.immutable(value)
      case value
      when Hash then value.to_h { |key, item| [immutable(key), immutable(item)] }.freeze
      when Array then value.map { |item| immutable(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end
  end
end
