# frozen_string_literal: true

require "base64"
require "mail"

module FlowchartRuntime
  # Queue-safe, standard Mail attachment options. Let Mail interpret raw content
  # and descriptors (including already encoded content), then transport the bytes
  # as ASCII Base64. Supplying encoding: "base64" tells Mail not to encode twice
  # when the delivery job reconstructs the attachment.
  class MailAttachments
    class Error < StandardError; end

    class << self
      def encode(attachments)
        invalid_input! unless attachments.is_a?(Hash)

        attachments.to_h do |filename, value|
          invalid_input! unless filename.is_a?(String) && filename.present?
          value = attachment_value(value)
          message = Mail.new
          message.attachments[filename] = value
          part = message.attachments.first
          options = part.header.fields.to_h do |field|
            [field.name.downcase.tr("-", "_").to_sym, field.value]
          end
          options.delete(:content_transfer_encoding)
          options.merge!(content: Base64.strict_encode64(part.body.decoded), encoding: "base64")
          [filename, options]
        end
      rescue Mail::Field::ParseError, Mail::UnknownEncodingType, ArgumentError, TypeError, EncodingError
        invalid_input!
      end

      private

      def attachment_value(value)
        return value if value.is_a?(String)
        invalid_input! unless value.is_a?(Hash)

        options = value.deep_symbolize_keys.except(:filename)
        content = options.values_at(:content, :data, :body)
        invalid_input! unless content.all? { |item| item.nil? || item.is_a?(String) }
        invalid_input! unless content.any? { |item| item.is_a?(String) }

        encoding = options[:transfer_encoding] || options[:encoding] || options[:content_transfer_encoding]
        if encoding
          invalid_input! unless (encoding.is_a?(String) || encoding.is_a?(Symbol)) && Mail::Encodings.get_encoding(encoding)
        end
        options
      end

      def invalid_input!
        raise Error, I18n.t("code_generator_communication.invalid_attachments")
      end
    end
  end
end
