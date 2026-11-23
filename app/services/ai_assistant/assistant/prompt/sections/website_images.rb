# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # Every image attached in this conversation, by token. The token is
        # the only way an attached photo reaches a website page, and the
        # "not placed yet" flag is the same one the server checks before it
        # nudges the model to place a forgotten photo.
        class WebsiteImages < Section
          heads "Website images"

          private

          def body
            return nil unless context.website_enabled?

            uploads = context.uploads.all
            return nil if uploads.empty?

            [
              "Images the admin attached in this conversation. Put one in an image field by writing its token " \
                "exactly as shown; the server copies it into the website's media.",
              uploads.map { |upload| row(upload) }.join("\n"),
              replay_note(uploads)
            ].compact.join("\n\n")
          end

          def row(upload)
            [
              "- `#{upload.token}` \"#{plain(upload.filename)}\"",
              shape(upload),
              upload.pending ? "not placed yet" : "already on the website"
            ].compact.join(" · ")
          end

          def shape(upload)
            size = "#{upload.width}x#{upload.height}" if upload.width.present? && upload.height.present?
            [upload.orientation, size].compact.join(" ").presence
          end

          def replay_note(uploads)
            limit = PromptBuilder::MAX_REPLAYED_IMAGES
            bytes = uploads.sum { |upload| upload.blob.byte_size.to_i }
            return nil if uploads.size <= limit && bytes <= PromptBuilder::MAX_REPLAYED_BYTES

            "You are shown the pictures of the newest messages only, at most #{limit}; for an older one rely on " \
              "its filename and what the conversation said about it."
          end
        end
      end
    end
  end
end
