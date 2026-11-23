# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      class CancellationsController < BaseController
        def create
          return no_subscription unless live_subscription
          result = ::Billing::Activities::CancelSubscription.call(subscription: live_subscription, immediately: false)
          respond_to_result(result, "scheduled", %i[scheduled cancelled unchanged])
        end

        def destroy
          return no_subscription unless live_subscription
          result = ::Billing::Activities::ResumeSubscription.call(subscription: live_subscription)
          respond_to_result(result, "resumed", %i[resumed unchanged])
        end

        private

        def respond_to_result(result, key, statuses)
          return render_subscription_failure(result) unless statuses.include?(result.status)
          key = "unchanged" if result.status == :unchanged
          redirect_to admin_settings_billing_subscription_path(current_customer_id), status: :see_other,
                      notice: t("admin_settings.flash.cancellations.#{key}")
        end

        def no_subscription
          render_subscription_failure(::Billing::Result.new(status: :invalid, reason: :no_active_subscription))
        end
      end
    end
  end
end
