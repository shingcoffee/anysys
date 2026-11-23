# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # Lets an admin revoke a tenant user's trusted (2FA-bypass) device. The
      # user is customer-scoped and the device is looked up through that user's
      # association, so a cross-tenant or cross-user id 404s. Admin/owner-only via
      # RouteAuthorization (admin path). Revoking = deleting the row; the browser
      # cookie then fails the digest lookup and MFA is required again.
      class UserTrustedDevicesController < ApplicationController
        dashboard_menu_item :modules

        def destroy
          user   = ::Authentication::User.where(customer_id: current_customer_id).find(params[:user_id])
          device = user.trusted_devices.find(params[:id])
          device.destroy!

          redirect_to admin_modules_authentication_user_path(current_customer_id, user),
                      notice: t("admin_modules.flash.users.trusted_device_revoked")
        end
      end
    end
  end
end
