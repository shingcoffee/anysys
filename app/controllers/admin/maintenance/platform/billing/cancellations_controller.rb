# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        # Platform-owner forced immediate cancellation of any tenant's subscription
        # (Area d — nested under subscriptions).
        #
        # create — immediately cancels the target subscription via
        #          CancelSubscription(immediately: true); financial history/debt remains.
        #          Accessible only to the platform owner (RouteAuthorization guards the
        #          /admin/maintenance/platform/ prefix).
        class CancellationsController < BaseController
          before_action :set_subscription

          # POST /81721200/admin/maintenance/platform/billing/subscriptions/:subscription_id/cancellation
          def create
            result = ::Billing::Activities::CancelSubscription.call(
              subscription: @subscription,
              immediately:  true
            )

            unless %i[cancelled unchanged].include?(result.status)
              @subscription.reload
              assign_subscription_detail
              return render_billing_failure(result, "admin/maintenance/platform/billing/subscriptions/show")
            end

            redirect_to admin_maintenance_platform_billing_subscription_path(
                          current_customer_id, @subscription
                        ),
                        status: :see_other,
                        notice: result.status == :unchanged ? t("admin_settings.flash.subscriptions.unchanged") :
                          t("maint_platform.flash.billing.subscription_cancelled", id: @subscription.id)
          end

          private

          def set_subscription
            @subscription = ::Billing::Subscription
                              .unscoped_by_tenant
                              .find(params[:subscription_id])
          end
        end
      end
    end
  end
end
