# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      # Tenant-scoped Lexxy / Action Text attachment upload controller.
      #
      # create — mirrors ActiveStorage::DirectUploadsController#create but
      #           explicitly stamps customer_id as defense-in-depth on top of
      #           the before_create initializer in active_storage_tenant.rb.
      #
      # show   — finds the blob within the current tenant scope and redirects
      #           to its service URL. A cross-tenant id → ActiveRecord::
      #           RecordNotFound → 404, enforcing isolation.
      #
      # Authorization: admin paths are auto-guarded by RouteAuthorization
      # (ADMIN_PATH_PATTERN); no per-controller before_action needed.
      class AttachmentsController < ApplicationController
        include ActiveStorage::SetCurrent

        dashboard_menu_item :modules
        before_action :require_email_module!, only: :create

        def create
          blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)
          blob.update!(customer_id: current_customer.id)
          render json: direct_upload_json(blob)
        end

        def show
          blob = ActiveStorage::Blob.for_customer(current_customer.id).find_by!(id: params[:id])
          redirect_to url_for(blob), allow_other_host: true
        end

        private

        def require_email_module!
          return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

          head :not_found
        end

        def blob_args
          params.require(:blob).permit(
            :filename, :byte_size, :checksum, :content_type, metadata: {}
          ).to_h.symbolize_keys
        end

        def direct_upload_json(blob)
          blob.as_json(root: false, methods: :signed_id).merge(
            direct_upload: {
              url:     blob.service_url_for_direct_upload,
              headers: blob.service_headers_for_direct_upload
            }
          )
        end
      end
    end
  end
end
