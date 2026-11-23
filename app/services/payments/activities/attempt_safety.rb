# frozen_string_literal: true

module Payments
  module Activities
    class AttemptSafety
      # Stripe retains keys for at least 24 hours. Leave an hour for transport
      # and worker scheduling; never reset this clock when retrying an attempt.
      STRIPE_REPLAY_WINDOW = 23.hours

      def self.definitive_rejection?(error)
        return false if error.respond_to?(:uncertain?) && error.uncertain?
        error.respond_to?(:definitive?) && error.definitive?
      end

      def self.expired?(record, provider:)
        provider == "stripe" && record.created_at <= STRIPE_REPLAY_WINDOW.ago
      end

      # The query can recover a lost remote identity or a capture, but neither
      # an empty search nor a query API error authorizes another financial write.
      def self.reconcile_expired!(customer:, payment:)
        return false unless expired?(payment, provider: payment.provider)

        begin
          Query.call(customer: customer, payment: payment)
        rescue Payments::Errors::Error => error
          # A capture can commit before its Billing projection raises. That
          # failure must reach the caller/queue rather than masquerade as recovery.
          raise if payment.reload.status == "succeeded"
          Rails.logger.warn("[payments.retry] reconciliation payment=#{payment.id}: #{error.class}: #{error.message}")
        end
        return true if payment.reload.status == "succeeded"

        payment.with_lock do
          context = payment.attempt_context.merge("review_reason" => "idempotency_window_expired")
          payment.update!(prepay_payload: payment.prepay_payload.merge(Payments::Payment::ATTEMPT_CONTEXT_KEY => context))
        end
        raise Payments::Errors::OrderInFlight, "payment attempt requires reconciliation before another write"
      end

      def self.guard_refund!(refund)
        return unless expired?(refund, provider: refund.payment.provider)

        refund.with_lock do
          return if refund.status == "succeeded"
          refund.update!(raw_notify: refund.raw_notify.merge("review_reason" => "idempotency_window_expired"))
        end
        raise Payments::Errors::OrderInFlight, "refund attempt requires reconciliation before another write"
      end

      # The current write facade still resolves its active account. Refuse a
      # retry if that is no longer the committed attempt's exact account.
      def self.assert_write_binding!(customer:, payment:)
        historical = Payments::CredentialResolver.for_payment(customer: customer, payment: payment)
        active = Payments::CredentialResolver.call(customer: customer, provider: payment.provider)
        unless historical.id == active.id && historical.merchant_id == active.merchant_id && historical.mode == active.mode
          raise Payments::Errors::CredentialsMissing, "payment attempt merchant is unavailable for a new write"
        end
      end
    end
  end
end
