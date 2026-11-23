# frozen_string_literal: true

module Member
  module Payments
    # Member self-service: cancel a card-recurring subscription.
    #
    # Authorization: member role enforced by RouteAuthorization (URL gate).
    # Subscription user isolation is enforced by scoping through the linked
    # PaymentMethod (same pattern as SubscriptionsController).
    #
    # This is NOT a preview surface — admin users are NOT admitted to writes.
    class SubscriptionCancellationsController < Member::BaseController
      before_action :require_payments_module!

      def create
        subscription = scoped_subscriptions.find(params[:subscription_id])
        ::Payments::Activities::CancelSubscription.call(
          customer:                current_customer,
          subscription:            subscription,
          detach_orphaned_token:   false
        )
        redirect_to member_payments_subscriptions_path(current_customer_id),
                    notice: t("member.flash.subscriptions.cancelled")
      rescue ::Payments::Errors::Error
        redirect_to member_payments_subscriptions_path(current_customer_id),
                    alert: t("comp_payments.flash.subscription_cancel_unavailable")
      end

      private

      def require_payments_module!
        return if FeatureModules::Module.enabled?(key: "payment", customer_id: current_customer.id)

        head :not_found
      end

      def scoped_subscriptions
        ::Payments::Subscription
          .for_current_customer
          .where(
            payment_method_id: ::Payments::PaymentMethod
                                  .for_current_customer
                                  .for_user(current_user.id)
                                  .select(:id)
          )
      end
    end
  end
end
