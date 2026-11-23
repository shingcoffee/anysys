# frozen_string_literal: true

module Websites
  module Activities
    # Copies an existing blob (an image attached in an assistant chat) into
    # tenant website media and returns its public site-media path. The copy is
    # a separate blob so the chat attachment and the published image have
    # independent lifecycles. Idempotent per (customer, source blob).
    class ImportMedia
      Result = Struct.new(:success?, :url, :blob, :created, :error, keyword_init: true)

      SOURCE_KEY = "assistant_source_blob_id"

      def self.call(customer:, blob:)
        new(customer: customer, blob: blob).call
      end

      def self.imports_for(customer:, blob:)
        ActiveStorage::Blob
          .where(customer_id: customer.id)
          .where("json_extract(metadata, '$.#{SOURCE_KEY}') = ?", blob.id)
      end

      # Ids among `blob_ids` whose import into this customer's media is one of
      # `urls`, the image values currently on the site's pages.
      def self.placed_source_ids(customer:, blob_ids:, urls:)
        return Set.new if blob_ids.empty? || urls.empty?

        ActiveStorage::Blob
          .where(customer_id: customer.id)
          .where("json_extract(metadata, '$.#{SOURCE_KEY}') IN (?)", blob_ids)
          .select { |copy| urls.include?(UploadMedia.media_url(customer, copy)) }
          .to_set { |copy| copy.metadata[SOURCE_KEY] }
      end

      # A blob stamped for another tenant is never copied into this one.
      def self.foreign?(blob, customer)
        blob.customer_id.present? && blob.customer_id != customer.id
      end

      def initialize(customer:, blob:)
        @customer = customer
        @blob = blob
      end

      def call
        return failure("image_missing") if @blob.nil?
        return failure("image_upload_failed") if self.class.foreign?(@blob, @customer)
        return failure("image_type") unless UploadMedia::TYPES.include?(@blob.content_type.to_s)
        return failure("image_too_large") if @blob.byte_size.to_i > UploadMedia::MAX_BYTES
        actual_type = @blob.open { |file| MediaPolicy.identified_type(file) }
        return failure("image_type") unless MediaPolicy.image_type?(actual_type)

        existing = self.class.imports_for(customer: @customer, blob: @blob).order(:id).first
        return success(existing, created: false) if MediaPolicy.public_image?(existing, customer_id: @customer.id)

        rendition = Websites::ImageFit.rendition(@blob)
        io = StringIO.new(rendition.bytes)
        type = MediaPolicy.identified_type(io)
        return failure("image_type") unless MediaPolicy.image_type?(type)
        return failure("image_too_large") if rendition.bytes.bytesize > UploadMedia::MAX_BYTES

        success(copy!(rendition, io, type), created: true)
      rescue ActiveStorage::FileNotFoundError
        failure("image_upload_failed")
      end

      private

      # The create-time stamp comes from Current.customer, which need not be
      # the customer the pages belong to, so customer_id is always forced.
      def copy!(rendition, io, type)
        copy = ActiveStorage::Blob.create_and_upload!(
          io: io,
          filename: @blob.filename.to_s,
          content_type: type,
          identify: false,
          metadata: { "website_media" => true, SOURCE_KEY => @blob.id, "width" => rendition.width, "height" => rendition.height }.compact
        )
        copy.update!(customer_id: @customer.id) unless copy.customer_id == @customer.id
        copy
      end

      def success(blob, created:)
        Result.new(success?: true, url: UploadMedia.media_url(@customer, blob), blob: blob, created: created)
      end

      def failure(key)
        Result.new(success?: false, error: I18n.t("website.errors.#{key}"))
      end
    end
  end
end
