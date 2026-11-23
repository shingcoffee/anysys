# frozen_string_literal: true

module Billing
  module Providers
    class Alipay
      def initialize(payment_method)
        @method = payment_method
      end

      def setup(return_url:)
        result = Payments::Gateway.billing_agreement(customer: Providers.platform, subscription: @method.payments_subscription,
          merchant_account: @method.merchant_account, return_url: return_url)
        action = result.fetch(:action)
        result.merge(action: action.merge(fields: action.fetch(:fields).to_h.transform_keys(&:to_s).transform_values(&:to_s)))
      end

      def query
        Payments::Gateway.billing_agreement(customer: Providers.platform, subscription: @method.payments_subscription,
          merchant_account: @method.merchant_account)
      end

      def revoke
        mandate = @method.payments_subscription
        return if mandate.psp_agreement_id.blank?
        Payments::Gateway.cancel_subscription(customer: Providers.platform, subscription: mandate, merchant_account: @method.merchant_account)
      end
    end
  end
end
