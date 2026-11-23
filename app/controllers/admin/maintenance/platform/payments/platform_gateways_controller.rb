# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Payments
        # Platform-owner toggle for whether a payment tender is offered to all
        # customers. Owner-only via RouteAuthorization (platform area). Validates
        # the provider against the gateway registry so unknown keys 404.
        class PlatformGatewaysController < ApplicationController
          dashboard_menu_item :maintenance

          def index
            @feature_module = ::FeatureModules::Module.find_by!(key: "payment")
            @gateways = ::Payments::Gateways.all.map do |gateway|
              [gateway, ::Payments::PlatformGateway.for_provider(gateway.key)]
            end
          end

          def update
            provider = params[:provider].to_s
            return head :not_found unless ::Payments::Gateways.keys.map(&:to_s).include?(provider)

            available = params[:available] == "1"
            ::Payments::PlatformGateway.for_provider(provider).update!(available: available)

            # Enabling a tender must back-fill its (provider, mode) credential rows
            # for customers that already have Payments enabled — otherwise the new
            # tender appears in their gallery but cannot be configured. The
            # provisioner is idempotent (find_or_create_by), so this is safe.
            # Turning it off must drop live status the same way module revoke
            # does: CredentialResolver keys off status: "active", so leftover
            # active rows would keep charging after the platform kill switch.
            if available
              backfill_existing_payment_customers!
            else
              disable_tenant_accounts!(provider)
            end

            redirect_to admin_maintenance_platform_module_settings_payment_gateways_path(current_customer_id),
                        notice: t("maint_platform.flash.payments.gateway_availability_updated")
          end

          private

          def disable_tenant_accounts!(provider)
            ::Payments::MerchantAccount.unscoped_by_tenant
                                       .where(provider: provider)
                                       .where.not(status: "disabled")
                                       .update_all(status: "disabled", updated_at: Time.current)
          end

          def backfill_existing_payment_customers!
            payment_module = ::FeatureModules::Module.find_by(key: "payment")
            return unless payment_module

            ::FeatureModules::CustomerAssignment
              .where(feature_module_id: payment_module.id, status: :active)
              .find_each do |assignment|
                ::FeatureModules::Payment::Provisioner.call(assignment.customer)
              end
          end
        end
      end
    end
  end
end
