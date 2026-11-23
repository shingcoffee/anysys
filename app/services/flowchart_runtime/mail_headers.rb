# frozen_string_literal: true

require "mail"

module FlowchartRuntime
  # Runtime RFC 5322 guard for generated mail steps. Compile-time literals are
  # already stripped; ctx values are not, so address lists and unstructured
  # fields are sanitized here before ActionMailer writes header lines.
  class MailHeaders
    class Error < StandardError; end

    ADDRESS_KEYS = %i[cc bcc from reply_to sender].freeze
    HEADER_NAME = /\A[A-Za-z0-9][A-Za-z0-9-]*\z/
    CONTROL_CHARS = /[\r\n\t\x00-\x1F\x7F]/
    COLLAPSE_CONTROL = /[\r\n\t\x00-\x1F\x7F]+/

    class << self
      def addresses!(value)
        parts = Array(value)
        invalid_input!(:invalid_recipients) unless parts.any? && parts.all? { |part| part.is_a?(String) || part.is_a?(Mail::Address) }
        serialized = parts.map(&:to_s)
        invalid_input!(:invalid_recipients) if serialized.any? { |part| part.match?(CONTROL_CHARS) }

        list = Mail::AddressList.new(serialized.join(", ")).addresses
        invalid_input!(:invalid_recipients) if list.empty? || list.any? { |address| address.local.blank? || address.domain.blank? }
        value.is_a?(Array) ? list.map(&:to_s) : list.first.to_s
      rescue Mail::Field::ParseError
        invalid_input!(:invalid_recipients)
      end

      def unstructured(value)
        return nil if value.nil?

        invalid_input!(:invalid_headers) unless value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric)
        value.to_s.gsub(COLLAPSE_CONTROL, " ")
      end

      def fields(headers)
        invalid_input!(:invalid_headers) unless headers.is_a?(Hash)

        headers.to_h do |key, value|
          name = unstructured(key).to_s.strip
          invalid_input!(:invalid_headers) unless HEADER_NAME.match?(name)
          [name, unstructured(value)]
        end
      end

      def recipients(options)
        invalid_input!(:invalid_headers) unless options.is_a?(Hash)

        options.to_h do |key, value|
          ADDRESS_KEYS.include?(key.to_sym) ? [key, addresses!(value)] : [key, value]
        end
      end

      private

      def invalid_input!(key)
        raise Error, I18n.t("code_generator_communication.#{key}")
      end
    end
  end
end
