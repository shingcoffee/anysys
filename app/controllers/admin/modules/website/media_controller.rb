# frozen_string_literal: true

module Admin
  module Modules
    module Website
      class MediaController < BaseController
        dashboard_menu_item :website_pages

        def create
          result = Websites::Activities::UploadMedia.call(customer: current_customer, file: params[:file])
          if result.success?
            render json: { url: result.url }
          else
            render json: { error: result.error }, status: :unprocessable_content
          end
        end
      end
    end
  end
end
