# frozen_string_literal: true

module Billing
  module Providers
    class Stripe
      def initialize(payment_method)
        @method = payment_method
      end

      def setup(return_url:)
        if @method.authorization_reference.present?
          intent = query
          interactive = %w[requires_payment_method requires_confirmation requires_action].include?(intent.fetch("status"))
          return { setup_intent_id: intent.fetch("id"), psp_customer_id: identity(intent.fetch("customer")),
            action: interactive ? { kind: :stripe_setup,
              publishable_key: @method.merchant_account.credential(:publishable_key), client_secret: intent.fetch("client_secret") } : nil }
        end
        Payments::Gateway.billing_vault_card(customer: Providers.platform, payment_method: @method,
          return_url: return_url, merchant_account: @method.merchant_account)
      end

      def query
        intent = if @method.authorization_reference.blank?
          Payments::Gateway.billing_find_setup_intent(customer: Providers.platform, payment_method: @method, merchant_account: @method.merchant_account)
        else
          Payments::Gateway.billing_setup_intent(customer: Providers.platform, payment_method: @method, merchant_account: @method.merchant_account)
        end
        return nil unless intent
        metadata = intent.fetch("metadata")
        account = @method.merchant_account
        context = @method.payments_subscription.metadata.fetch("billing_authorization_context", {})
        unless metadata["billing_payment_method_id"].to_s == @method.id.to_s && metadata["billing_customer_id"].to_s == @method.customer_id.to_s &&
            metadata["merchant_account_id"].to_s == account.id.to_s &&
            (context["merchant_id"].blank? || metadata["merchant_id"] == context["merchant_id"]) &&
            (@method.authorization_reference.blank? || intent.fetch("id") == @method.authorization_reference)
          raise Payments::Errors::TenantMismatch, "Stripe setup identity mismatch"
        end
        token = @method.payments_subscription.payment_method
        if token && !(token.provider == "stripe" && token.customer_id == account.customer_id && token.user_id.nil? &&
            token.billing_customer_id == @method.customer_id && token.billing_authorized_by_id == @method.authorized_by_id &&
            token.psp_customer_id == identity(intent.fetch("customer")))
          raise Payments::Errors::TenantMismatch, "Stripe setup token ownership mismatch"
        end
        intent
      end

      def revoke
        return :pending if @method.authorization_reference.blank?
        token = @method.payments_subscription&.payment_method
        if token && !(token.provider == "stripe" && token.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID && token.user_id.nil? &&
            token.billing_customer_id == @method.customer_id && token.billing_authorized_by_id == @method.authorized_by_id)
          raise Payments::Errors::TenantMismatch, "cannot revoke an unrelated billing token"
        end
        if @method.authorization_reference.present? && (!token || !token.confirmed?)
          intent = query
          unless %w[succeeded canceled].include?(intent["status"])
            Payments::Gateway.billing_cancel_setup_intent(customer: Providers.platform, payment_method: @method, merchant_account: @method.merchant_account)
          end
        end
        return if !token || !token.confirmed?
        Payments::Gateway.detach_token(customer: Providers.platform, payment_method: token, merchant_account: @method.merchant_account)
      rescue Payments::Errors::ApiError => error
        raise unless error.payload.dig("error", "code") == "resource_missing"
      end

      private

      def identity(value) = value.is_a?(Hash) ? value.fetch("id") : value
    end
  end
end
