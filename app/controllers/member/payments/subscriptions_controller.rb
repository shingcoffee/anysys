# frozen_string_literal: true

module Member
  module Payments
    # Member self-service: view own recurring subscriptions.
    #
    # Authorization: member role enforced by RouteAuthorization (URL gate).
    # Subscriptions have NO user_id column; user isolation is enforced by
    # scoping through the linked PaymentMethod's user_id. Only subscriptions
    # whose payment_method belongs to current_user are visible.
    #
    # Non-card subscriptions (QR/H5/JSAPI) have payment_method_id: nil and
    # are NOT surfaced here — they are admin-managed. This controller renders
    # only card-recurring subscriptions owned by the member.
    #
    # This is NOT a preview surface — admin users are NOT admitted.
    class SubscriptionsController < Member::BaseController
      before_action :require_payments_module!
      before_action :set_subscription, only: :show

      def index
        @subscriptions = scoped_subscriptions.order(created_at: :desc).limit(100)
        render subscriptions_component(@subscriptions)
      end

      def show
        render subscriptions_component([ @subscription ])
      end

      private

      def require_payments_module!
        return if FeatureModules::Module.enabled?(key: "payment", customer_id: current_customer.id)

        head :not_found
      end

      def subscriptions_component(subscriptions)
        ::Payments::Member::SubscriptionsComponent.new(
          subscriptions:   subscriptions,
          cancel_url_for:  ->(sub) { member_payments_subscription_cancellation_path(current_customer_id, sub) },
          recovery_for:    ->(sub) { recovery_context(sub) },
          publishable_key: stripe_publishable_key
        )
      end

      # On-session SCA recovery: a paused subscription whose latest charge stalled
      # on issuer authentication has a pending payment carrying the PaymentIntent
      # client_secret. Surface it so the member can complete 3DS in the browser.
      def recovery_context(sub)
        return nil unless sub.status == "paused"

        payment = recovery_payment_for(sub)
        return nil unless payment

        { client_secret: payment.recovery_client_secret }
      end

      def recovery_payment_for(sub)
        prefix = "sub-#{sub.id}-"
        ::Payments::Payment
          .for_current_customer
          .joins(:payment_order)
          .where("payment_orders.external_ref LIKE ?",
                 "#{::Payments::Payment.sanitize_sql_like(prefix)}%")
          .where("LENGTH(payment_orders.external_ref) = ?", prefix.length + PERIOD_DATE_LENGTH)
          .where(status: "pending")
          .order(created_at: :desc)
          .detect(&:requires_action?)
      end

      # ChargeDueSubscriptions mints `sub-<id>-<YYYY-MM-DD>`. A bare
      # `sub-<id>-%` LIKE also matches `sub-<id><more digits>-…` (sub 1 vs
      # sub 10). Pin the suffix to a calendar date so the prefix cannot widen.
      PERIOD_DATE_LENGTH = "YYYY-MM-DD".length

      # Resolve the publishable key through the SAME (customer, provider, mode)
      # lookup Payments::Gateway uses to create the charge in the first place
      # (Payments::CredentialResolver's default mode tracks Rails.env.production?).
      # A tenant may have both a sandbox and a production Stripe account active at
      # once; grabbing "whichever active row comes back first" can hand the browser
      # a publishable key from a different mode than the one that minted the
      # client_secret being confirmed, which Stripe.js rejects outright.
      def stripe_publishable_key
        ::Payments::CredentialResolver.call(customer: current_customer, provider: "stripe")
                                       .credential(:publishable_key)
      rescue ::Payments::Errors::CredentialsMissing
        nil
      end

      # Scope subscriptions to the current tenant via the payment_method's user_id.
      # Subscriptions have no direct user_id column, so we join through
      # PaymentMethod which does carry user_id + customer_id.
      def scoped_subscriptions
        ::Payments::Subscription
          .for_current_customer
          .includes(:payment_method)
          .where(
            payment_method_id: ::Payments::PaymentMethod
                                  .for_current_customer
                                  .for_user(current_user.id)
                                  .select(:id)
          )
      end

      def set_subscription
        @subscription = scoped_subscriptions.find(params[:id])
      end
    end
  end
end
