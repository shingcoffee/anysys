# frozen_string_literal: true

module Websites
  # Public bytes for explicitly classified tenant website images. A signed id
  # alone must never make a private attachment or executable content public.
  class AssetsController < ApplicationController
    include Websites::CurrentSite

    layout false

    def show
      return head :not_found unless website_module_enabled?

      blob = ActiveStorage::Blob.find_signed(params[:signed_id])
      return head :not_found unless Websites::MediaPolicy.public_image?(blob, customer_id: current_customer_id)

      bytes = blob.download
      return head :not_found unless bytes.bytesize == blob.byte_size

      content_type = Websites::MediaPolicy.identified_type(StringIO.new(bytes))
      return head :not_found unless Websites::MediaPolicy.image_type?(content_type) && content_type == blob.content_type

      expires_in 1.year, public: true
      response.headers["X-Content-Type-Options"] = "nosniff"
      send_data bytes,
                filename: blob.filename.to_s,
                type: content_type,
                disposition: :inline
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError
      head :not_found
    end
  end
end
