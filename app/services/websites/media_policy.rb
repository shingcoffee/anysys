# frozen_string_literal: true

require "marcel"

module Websites
  # Filename and client MIME are hints, not proof of an image. This is the
  # shared publication boundary for uploads/imports and the serving controller.
  module MediaPolicy
    IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    MAX_BYTES = 8.megabytes

    module_function

    def identified_type(io)
      return unless io.respond_to?(:read) && io.respond_to?(:rewind)

      io.rewind
      Marcel::MimeType.for(io)
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    def image_type?(type)
      IMAGE_TYPES.include?(type)
    end

    def public_image?(blob, customer_id:)
      customer_id.present? && blob.present? && blob.customer_id.to_s == customer_id.to_s &&
        blob.metadata.is_a?(Hash) && blob.metadata["website_media"] == true && image_type?(blob.content_type) &&
        blob.byte_size.positive? && blob.byte_size <= MAX_BYTES
    end
  end
end
