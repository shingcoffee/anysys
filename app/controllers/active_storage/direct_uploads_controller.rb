# frozen_string_literal: true

# Rails' default direct-upload endpoint is unauthenticated and never stamps
# customer_id. Tenant uploads go through Admin::Modules::Emails::AttachmentsController.
module ActiveStorage
  class DirectUploadsController < BaseController
    def create
      head :not_found
    end
  end
end
