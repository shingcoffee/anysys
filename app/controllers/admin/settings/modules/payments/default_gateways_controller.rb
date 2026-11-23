# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Payments
        # Sets the tenant's default payment gateway. Admin-scoped (inherits the
        # payments-settings auth guard); tenant-scoped via current_customer.
        class DefaultGatewaysController < ::Admin::Modules::Payments::BaseController
          dashboard_menu_item :settings

          def update
            ::Payments::SetDefaultGateway.call(customer: current_customer, provider: params[:provider])
            redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                        notice: t("admin_settings.flash.default_gateways.updated")
          rescue ArgumentError
            redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                        alert: t("comp_payments.flash.gateway_not_eligible", provider: params[:provider])
          end
        end
      end
    end
  end
end
