# frozen_string_literal: true

module Payments
  module Activities
    class CancelSubscription
      def self.call(customer:, subscription:, detach_orphaned_token: true)
        if subscription.billing_owned?
          raise Payments::Errors::Error, "billing mandates are cancelled from Billing"
        end

        Payments::Gateway.cancel_subscription(customer: customer, subscription: subscription)
        subscription.mark_cancelled!

        # For card-recurring subscriptions: revoke the vaulted token at the PSP
        # if no other active subscription still references the same PaymentMethod.
        # This prevents stranded tokens when a user cancels their last card plan.
        # Member self-service passes detach_orphaned_token: false so cancelling
        # one plan does not yank a vaulted card still needed for later checkouts.
        if detach_orphaned_token && subscription.card_recurring? && subscription.payment_method.present?
          self.detach_orphaned_token(customer: customer, payment_method: subscription.payment_method)
        end

        subscription
      end

      def self.detach_orphaned_token(customer:, payment_method:)
        still_in_use = Payments::Subscription
                         .unscoped_by_tenant
                         .where(payment_method_id: payment_method.id,
                                status: %w[pending_sign active paused])
                         .exists?
        return if still_in_use

        Payments::Gateway.detach_token(customer: customer, payment_method: payment_method)
        payment_method.mark_removed!
      rescue Payments::Errors::Error => e
        # Token detach is best-effort: log and continue. The subscription is
        # already cancelled so a PSP error here must not roll it back.
        Rails.logger.warn("[payments.cancel_subscription] detach_token failed: #{e.message}")
      end
    end
  end
end
