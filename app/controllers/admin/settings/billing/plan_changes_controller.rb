# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      class PlanChangesController < BaseController
        def destroy
          subscription = ::Billing::Subscription.for_current_customer.live
                         .order(created_at: :desc, id: :desc).first!
          change = ::Billing::PlanChange.for_current_customer
                   .where(billing_subscription_id: subscription.id, status: %w[awaiting_payment scheduled]).first!
          result = ::Billing::Activities::CancelPlanChange.call(subscription: subscription, plan_change: change)
          return render_subscription_failure(result) unless %i[cancelled unchanged].include?(result.status)

          redirect_to admin_settings_billing_subscription_path(current_customer_id), status: :see_other,
                      notice: t("admin_settings.flash.subscriptions.plan_change_cancelled")
        end
      end
    end
  end
end
