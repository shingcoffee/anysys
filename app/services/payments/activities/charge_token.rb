# frozen_string_literal: true

module Payments
  module Activities
    # Off-session charge against a vaulted PaymentMethod token.
    #
    # Creates a new Payments::Payment row, calls gateway#charge_token,
    # then marks the payment succeeded or failed from the PSP result.
    #
    # Raises Payments::Errors::TenantMismatch when the PaymentMethod does
    # not belong to the given customer — prevents cross-tenant token charges.
    #
    # Raises Payments::Errors::CardDeclined when the PSP returns a non-succeeded
    # status so that callers (e.g. the cron job) can distinguish a network/API
    # error (ApiError) from a soft decline and skip advancing next_charge_at.
    #
    # Returns the Payments::Payment record on success.
    class ChargeToken
      def self.call(customer:, order:, payment_method:, payment: nil)
        if payment_method.customer_id != customer.id || order.customer_id != customer.id
          raise Payments::Errors::TenantMismatch,
                "PaymentMethod #{payment_method.id} does not belong to customer #{customer.id}"
        end

        # Reusing a stalled row keeps out_trade_no stable, so the PSP-side
        # Idempotency-Key dedups a retry after an ambiguous transport failure.
        payment = order.with_lock do
          if order.status.in?(Payments::Order::SETTLED_STATUSES)
            captured = order.payments.find_by(status: "succeeded", provider: payment_method.provider)
            return captured if captured
            raise Payments::Errors::OrderSettled, "order has already settled"
          end
          payment ||= order.payments.where(provider: payment_method.provider, status: %w[created pending]).first
          payment ||= Payments::Payment.create!(
            payment_order: order, provider: payment_method.provider, flow: "card",
            out_trade_no: Payments::OutTradeNo.generate(prefix: "ct", customer_id: customer.id),
            amount: order.amount, user_id: payment_method.user_id
          )
          unless payment.provider == payment_method.provider && payment.flow == "card"
            raise Payments::Errors::TenantMismatch, "payment attempt does not match the supplied payment method"
          end
          context = PrepareAttempt.call(customer: customer, order: order, payment: payment,
                                        operation: "charge_token",
                                        attributes: { payment_method_id: payment_method.id,
                                                      psp_payment_method_id: payment_method.psp_payment_method_id })
          if context["payment_method_id"].present? &&
             (context["payment_method_id"] != payment_method.id ||
              context["psp_payment_method_id"] != payment_method.psp_payment_method_id)
            raise Payments::Errors::OrderInFlight, "payment method changed while the remote outcome is unresolved"
          end
          payment
        end

        return payment if AttemptSafety.reconcile_expired!(customer: customer, payment: payment)
        if payment.status == "pending"
          raise Payments::Errors::PaymentRequiresAction, "card charge is already awaiting confirmation"
        end

        AttemptSafety.assert_write_binding!(customer: customer, payment: payment)
        begin
          result = Payments::Gateway.charge_token(
            customer:       customer,
            order:          order,
            payment:        payment,
            payment_method: payment_method
          )
        rescue Payments::Errors::ApiError => e
          # The exception class alone does not prove that the write was rejected.
          # Only an explicit definitive classification may retire its identity.
          payment.mark_failed!(reason: "#{e.class}: #{e.message}") if AttemptSafety.definitive_rejection?(e)
          raise
        end
        # A TransportError (ambiguous — the PSP may have processed it) intentionally
        # propagates with the row left "created": the caller's stalled-row lookup
        # reuses it on the next tick instead of minting a new out_trade_no.

        case result[:status]
        when :succeeded
          raw = result[:raw].is_a?(Hash) ? result[:raw] : {}
          currency = result[:currency] || raw["currency"].presence
          amount = result[:amount]
          amount ||= HandleWebhook.stripe_amount(raw, currency || order.currency) if payment.provider == "stripe"
          captured = HandleWebhook.finalize_success!(
            payment, psp_id: result[:psp_transaction_id],
            at: result[:settled_at] || result[:paid_at] || HandleWebhook.stripe_capture_time(raw), notify: raw,
            notified_amount: amount, notified_currency: currency
          )
          raise Payments::Errors::PaymentRequiresAction, "card capture does not match the recorded payment" unless captured
        when :requires_action
          # Issuer requires interactive authentication (3DS/SCA). Off-session we
          # cannot satisfy it — but we CAN let the member complete it on-session:
          # stash the PaymentIntent client_secret on the (non-terminal) payment,
          # then raise so the caller pauses the subscription instead of granting a
          # free period. The paused-sub recovery UI reads back this client_secret.
          payment.with_lock do
            if payment.psp_transaction_id.blank? && result[:psp_transaction_id].present?
              payment.update!(psp_transaction_id: result[:psp_transaction_id])
            end
          end
          payment.mark_pending!(
            "client_secret"         => result[:client_secret],
            "requires_action"       => true,
            "psp_payment_intent_id" => result[:psp_transaction_id]
          )
          return payment if payment.reload.status == "succeeded"
          raise Payments::Errors::PaymentRequiresAction,
                "Card charge for payment #{payment.out_trade_no} requires interactive authentication"
        when :pending
          # Any other non-terminal status: do not advance / grant service.
          return payment if payment.reload.status == "succeeded"
          raise Payments::Errors::PaymentRequiresAction,
                "Card charge for payment #{payment.out_trade_no} is not yet complete"
        when :failed, :closed
          payment.mark_failed!(reason: result[:raw].to_s)
          return payment if payment.reload.status == "succeeded"
          raise Payments::Errors::CardDeclined,
                "Card charge declined for payment #{payment.out_trade_no}"
        else
          raise Payments::Errors::TransportError, "card charge returned an unknown outcome"
        end

        payment
      end
    end
  end
end
