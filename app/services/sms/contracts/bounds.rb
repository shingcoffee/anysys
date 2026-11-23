# frozen_string_literal: true

module Sms
  module Contracts
    module Bounds
      CUSTOM_KEY = /\A[a-z][a-z0-9_]{0,63}\z/
      TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})\z/
      module_function

      def text?(value, bytes:, required: false)
        return !required if value.nil?

        value.is_a?(String) && value.valid_encoding? &&
          (value.encoding == Encoding::UTF_8 || value.ascii_only?) && value.bytesize <= bytes &&
          (!required || value.present?)
      end

      def scalar?(value)
        value.nil? || value == true || value == false || value.is_a?(Integer) ||
          (value.is_a?(Float) && value.finite?) || text?(value, bytes: 1024, required: false)
      end

      def object?(value, bytes:)
        value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } && JSON.generate(value).bytesize <= bytes
      rescue JSON::GeneratorError, EncodingError, SystemStackError
        false
      end

      def custom_attributes?(value)
        object?(value, bytes: 8192) && value.size <= 32 && value.all? do |key, item|
          key.match?(CUSTOM_KEY) && scalar?(item)
        end
      end

      def timezone?(value, optional: true)
        return optional if value.nil? || value == ""
        return false unless text?(value, bytes: 100, required: true)

        TZInfo::Timezone.get(value)
        true
      rescue TZInfo::InvalidTimezoneIdentifier
        false
      end

      def country?(value)
        value.is_a?(String) && value.match?(/\A[A-Z]{2}\z/) && Phonelib.phone_data.key?(value)
      end

      def time(value)
        return value.to_time.utc.round(6) if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return unless value.is_a?(String) && TIME_FORMAT.match?(value)

        DateTime.iso8601(value)
        Time.iso8601(value).utc.round(6)
      rescue ArgumentError
        nil
      end
    end
  end
end
