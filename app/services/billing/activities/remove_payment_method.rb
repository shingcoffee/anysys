# frozen_string_literal: true

module Billing
  module Activities
    class RemovePaymentMethod
      def self.call(payment_method:)
        Billing::Result.transaction(payment_method.customer) do
          payment_method.reload
          return Billing::Result.new(status: :unchanged, payment_method: payment_method) if payment_method.removed?
          mandate = payment_method.payments_subscription
          review = payment_method.merchant_account.nil?
          if mandate
            unless mandate.billing_owned? && mandate.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID && mandate.provider == payment_method.provider
              raise Payments::Errors::TenantMismatch, "cannot remove unrelated mandate"
            end
            mandate.update!(status: "cancelled", cancelled_at: Time.current, next_charge_at: nil)
            token = mandate.payment_method
            if token
              if token.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID && token.provider == payment_method.provider && token.user_id.nil? &&
                  token.billing_customer_id == payment_method.customer_id && token.billing_authorized_by_id == payment_method.authorized_by_id
                token.mark_removed!
              else
                review = true
              end
            end
          end
          payment_method.update!(status: "removed", is_default: false, requested_default: false, removed_at: Time.current,
            revocation_state: "pending", revocation_next_attempt_at: Time.current,
            failure_code: review ? "historical_authorization_review" : payment_method.failure_code)
          Billing::Result.new(status: :removed, payment_method: payment_method, reason: :revocation_pending)
        end
      end
    end
  end
end
