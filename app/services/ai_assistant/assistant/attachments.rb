# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Attachments
      IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
      MAX_FILES = 8
      MAX_BYTES = 5.megabytes
      # A message's images are resent to the vendor together, base64-encoded,
      # so one message must fit in a single request.
      MAX_TOTAL_BYTES = 20.megabytes

      module_function

      def accept = IMAGE_TYPES.join(",")

      def supported?
        klass = AiAssistant::ProviderSettings.active_for(:generation)&.provider_class
        klass.nil? || klass.supports_images?
      end

      def present?(files)
        normalize(files).any?
      end

      def normalize(files)
        Array(files).flatten.compact_blank
      end

      def attach!(record, files)
        normalize(files).each { |upload| record.images.attach(upload) }
      end

      def validate(files, errors:, attribute: :images)
        list = normalize(files)
        return if list.empty?

        unless supported?
          errors.add(attribute, I18n.t("ai_assistant.errors.images_unsupported"))
          return
        end

        if list.size > MAX_FILES
          errors.add(attribute, I18n.t("ai_assistant.errors.too_many_images", count: MAX_FILES))
          return
        end

        if (error = list.lazy.filter_map { |file| file_error(file) }.first)
          errors.add(attribute, error)
        elsif list.sum { |file| byte_size_for(file) } > MAX_TOTAL_BYTES
          errors.add(attribute, I18n.t("ai_assistant.errors.images_too_large_total"))
        end
      end

      def file_error(file)
        type = file.respond_to?(:content_type) ? file.content_type.to_s : ""
        return I18n.t("ai_assistant.errors.invalid_image_type") unless IMAGE_TYPES.include?(type)

        size = byte_size_for(file)
        I18n.t("ai_assistant.errors.image_too_large") if size.nil? || size > MAX_BYTES
      end

      def byte_size_for(file)
        return file.byte_size if file.respond_to?(:byte_size)
        return file.size if file.respond_to?(:size)

        nil
      end
    end
  end
end
