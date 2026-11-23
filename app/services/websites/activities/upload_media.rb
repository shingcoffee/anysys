# frozen_string_literal: true

module Websites
  module Activities
    # Tenant-scoped image upload for marketing sections. Wraps ActiveStorage so
    # callers only see a public site-media path.
    class UploadMedia
      Result = Struct.new(:success?, :url, :error, keyword_init: true)

      MAX_BYTES = MediaPolicy::MAX_BYTES
      TYPES = MediaPolicy::IMAGE_TYPES

      def self.call(customer:, file:)
        new(customer: customer, file: file).call
      end

      def self.media_url(customer, blob)
        "/#{customer.id}/site/media/#{blob.signed_id}"
      end

      def initialize(customer:, file:)
        @customer = customer
        @file = file
      end

      def call
        return failure(I18n.t("website.errors.image_missing")) if @file.blank?
        return failure(I18n.t("website.errors.image_too_large")) if oversized?
        type = MediaPolicy.identified_type(@file)
        return failure(I18n.t("website.errors.image_type")) unless MediaPolicy.image_type?(type)

        blob = ActiveStorage::Blob.create_and_upload!(
          io: @file,
          filename: filename,
          content_type: type,
          identify: false,
          metadata: { website_media: true }
        )
        blob.update!(customer_id: @customer.id) unless blob.customer_id == @customer.id
        Result.new(success?: true, url: self.class.media_url(@customer, blob))
      end

      private

      def filename
        @file.original_filename.presence || "image"
      end

      def oversized?
        size = @file.size if @file.respond_to?(:size)
        !size.is_a?(Integer) || size <= 0 || size > MAX_BYTES
      end

      def failure(message)
        Result.new(success?: false, error: message)
      end
    end
  end
end
