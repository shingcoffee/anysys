# frozen_string_literal: true

module Websites
  module Assistant
    # The images an admin attached in one assistant conversation, addressed by
    # `upload:<attachment id>` tokens. A token only resolves through #find, so
    # the model can never reach an attachment from another conversation or
    # tenant by guessing ids.
    class Uploads
      TOKEN = /\Aupload:(\d+)\z/
      ASPECT_TOLERANCE = 1.1

      Upload = Struct.new(
        :token,
        :attachment,
        :blob,
        :filename,
        :width,
        :height,
        :orientation,
        :message_id,
        :pending,
        keyword_init: true
      )

      class << self
        def token_for(attachment)
          "upload:#{attachment.id}"
        end

        def token?(value)
          value.is_a?(String) && TOKEN.match?(value)
        end

        def ordered(message)
          message.images.attachments.sort_by(&:id)
        end

        def manifest_line(attachments)
          list = Array(attachments)
          return nil if list.empty?

          "Attached images, in order: #{list.map { |attachment| manifest_entry(attachment) }.join('; ')}"
        end

        def dimensions(blob)
          metadata = blob.metadata.to_h.stringify_keys
          width = metadata["width"].to_i
          height = metadata["height"].to_i
          width.positive? && height.positive? ? [width, height] : [nil, nil]
        end

        def orientation(width, height)
          return nil unless width && height
          return "landscape" if width > height * ASPECT_TOLERANCE
          return "portrait" if height > width * ASPECT_TOLERANCE

          "square"
        end

        private

        def manifest_entry(attachment)
          blob = attachment.blob
          entry = %(#{token_for(attachment)} "#{blob.filename}")
          width, height = dimensions(blob)
          return entry unless width

          "#{entry} (#{orientation(width, height)} #{width}x#{height})"
        end
      end

      def initialize(conversation:)
        @conversation = conversation
      end

      def all
        @all ||= load_uploads
      end

      def find(token)
        return nil unless self.class.token?(token)

        all.find { |upload| upload.token == token }
      end

      def pending
        all.select(&:pending)
      end

      private

      def load_uploads
        return [] if @conversation.nil?

        pairs = user_messages.flat_map do |message|
          self.class.ordered(message).map { |attachment| [message, attachment] }
        end
        return [] if pairs.empty?

        placed = Websites::Activities::ImportMedia.placed_source_ids(
          customer: @conversation.customer,
          blob_ids: pairs.filter_map { |_, attachment| attachment.blob&.id },
          urls: site_image_urls
        )
        pairs.filter_map { |message, attachment| build(message, attachment, placed) }
      end

      # What is on the pages now rather than what was ever imported, so a
      # photo the admin has since removed is offered for placement again.
      def site_image_urls
        sections = WebsitePage.where(customer_id: @conversation.customer_id).pluck(:sections)
        SchemaValidator.image_values(sections).to_set
      end

      def user_messages
        AiAssistant::Message
          .where(conversation_id: @conversation.id, customer_id: @conversation.customer_id, role: "user")
          .includes(images_attachments: :blob)
          .order(:id)
      end

      def build(message, attachment, placed)
        blob = attachment.blob
        return nil if blob.nil? || Websites::Activities::ImportMedia.foreign?(blob, @conversation.customer)

        width, height = self.class.dimensions(blob)
        Upload.new(
          token: self.class.token_for(attachment),
          attachment: attachment,
          blob: blob,
          filename: blob.filename.to_s,
          width: width,
          height: height,
          orientation: self.class.orientation(width, height),
          message_id: message.id,
          pending: !placed.include?(blob.id)
        )
      end
    end
  end
end
