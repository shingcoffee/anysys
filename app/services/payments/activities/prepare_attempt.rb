# frozen_string_literal: true

module Payments
  module Activities
    # Persist before outbound writes, under the caller's aggregate lock. A retry
    # must use the same merchant, order contents and operation parameters.
    class PrepareAttempt
      def self.call(customer:, order:, payment:, operation:, attributes: {})
        unless order.customer_id == customer.id && payment.customer_id == customer.id &&
               payment.payment_order_id == order.id
          raise Payments::Errors::TenantMismatch, "payment attempt does not belong to the supplied order/customer"
        end

        context = payment.attempt_context
        contents = {
          "operation" => operation,
          "provider" => payment.provider,
          "flow" => payment.flow,
          "user_id" => payment.user_id,
          "external_ref" => order.external_ref,
          "amount" => payment.amount.to_s("F"),
          "currency" => order.currency,
          "subject" => order.subject,
          "body" => order.body,
          "expires_at" => order.expires_at&.iso8601(6)
        }
        if context.present?
          unless contents.all? { |key, value| context[key] == value } && payment.amount == order.amount
            raise Payments::Errors::OrderInFlight, "payment attempt contents changed while the remote outcome is unresolved"
          end
          return context
        end

        account = Payments::CredentialResolver.call(customer: customer, provider: payment.provider)
        context = contents.merge(attributes.stringify_keys).merge(
          "merchant_account_id" => account.id,
          "merchant_id" => account.merchant_id,
          "mode" => account.mode
        )
        payment.update!(prepay_payload: payment.prepay_payload.merge(Payments::Payment::ATTEMPT_CONTEXT_KEY => context))
        context
      end
    end
  end
end
