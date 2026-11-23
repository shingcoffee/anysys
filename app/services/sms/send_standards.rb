# frozen_string_literal: true

require "json"

module Sms
  # SQL-free shape validation shared with admission before idempotency lookup.
  # Limits are UTF-8 bytes; the total includes JSON escaping and key overhead.
  # Callers normalize nil vars to {} and blank idempotency strings to nil.
  class SendStandards
    MAX_KEY_BYTES = 128
    MAX_VALUE_BYTES = 1_024
    MAX_PAYLOAD_BYTES = 8_192
    MAX_VARIABLES = 64
    TEMPLATE_KEY_FORMAT = /\A[a-z0-9_]+\z/

    def self.validation_errors(to:, template_key:, vars:, idempotency_key: nil)
      errors = {}
      errors[:to] = I18n.t("sms_standards.validation.phone") unless PhoneNumber.new(to).valid?
      errors[:template_key] = I18n.t("sms_standards.validation.template_key", limit: MAX_KEY_BYTES) unless template_key_valid?(template_key)
      errors[:idempotency_key] = I18n.t("sms_standards.validation.idempotency_key", limit: MAX_KEY_BYTES) unless idempotency_key_valid?(idempotency_key)
      unless vars_valid?(vars)
        errors[:vars] = I18n.t("sms_standards.validation.vars", value_limit: MAX_VALUE_BYTES, total_limit: MAX_PAYLOAD_BYTES, count_limit: MAX_VARIABLES)
      end
      errors
    end

    def self.template_key_valid?(value)
      value.is_a?(String) && utf8_string?(value) && value.bytesize <= MAX_KEY_BYTES && value.match?(TEMPLATE_KEY_FORMAT)
    end

    def self.idempotency_key_valid?(value)
      value.nil? || (value.is_a?(String) && utf8_string?(value) && value.bytesize <= MAX_KEY_BYTES)
    end

    def self.vars_valid?(vars)
      return false unless vars.is_a?(Hash) && vars.size <= MAX_VARIABLES
      return false unless vars.all? do |key, value|
        (key.is_a?(String) || key.is_a?(Symbol)) && utf8_string?(key.to_s) &&
          key.to_s.present? && key.to_s.bytesize <= MAX_KEY_BYTES && scalar_value?(value)
      end
      return false unless vars.keys.map(&:to_s).uniq.size == vars.size

      JSON.generate(vars).bytesize <= MAX_PAYLOAD_BYTES
    rescue JSON::GeneratorError, EncodingError
      false
    end

    def self.scalar_value?(value)
      case value
      when String then utf8_string?(value) && value.present? && value.bytesize <= MAX_VALUE_BYTES
      when Integer
        # Reject huge programmatic integers before allocating their decimal
        # representation. JSON input itself only produces finite scalar numbers.
        value.bit_length <= MAX_VALUE_BYTES * 4 && value.to_s.bytesize <= MAX_VALUE_BYTES
      when Float, BigDecimal then value.finite? && value.to_s.bytesize <= MAX_VALUE_BYTES
      else false
      end
    end
    private_class_method :scalar_value?

    def self.utf8_string?(value)
      value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
    end
    private_class_method :utf8_string?
  end
end
