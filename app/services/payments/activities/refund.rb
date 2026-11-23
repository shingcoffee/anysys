# frozen_string_literal: true

module Payments
  module Activities
    class Refund
      # Two concurrent admin clicks for the same refund would otherwise both
      # find no in-flight row, both create a new Payments::Refund, and both call
      # the PSP — causing a double refund. Serialize find-or-create on a
      # row-level lock on the parent Payment, which is the natural aggregate
      # boundary here.
      def self.call(customer:, payment:, amount:, reason: nil)
        currency = payment.payment_order&.currency || "CNY"
        begin
          amount = Payments::Money.normalize(amount, currency)
        rescue ArgumentError
          raise Payments::Errors::RefundNotAllowed.new(
            "refund amount must be positive", code: :non_positive
          )
        end

        # Serialize concurrent requests on the payment row, but ONLY around local
        # bookkeeping — the refund row (and its out_refund_no idempotency key)
        # must be COMMITTED before the PSP call, so an ambiguous transport failure
        # cannot roll it back and a retry re-uses the same PSP-side idempotency
        # key instead of minting a new one (double-refund).
        refund = payment.with_lock do
          # Look for an in-flight row to reuse BEFORE checking the ceiling: a
          # stuck "requested"/"processing" row already reserves its own amount,
          # so re-running validate_refundable! against it here would count it
          # against itself and make retrying a full (or ceiling-exhausting)
          # refund permanently unreachable. The ceiling only needs to gate the
          # creation of a genuinely NEW refund row.
          Payments::Refund.where(payment_id: payment.id, amount: amount,
                                 status: %w[requested processing]).first ||
            begin
              validate_refundable!(payment, amount)
              Payments::Refund.create!(
                payment: payment,
                out_refund_no: Payments::OutTradeNo.generate(prefix: "rf", customer_id: customer.id),
                amount: amount, reason: reason
              )
            end
        end

        return refund if refund.reload.status == "succeeded"
        AttemptSafety.guard_refund!(refund)
        begin
          res = Payments::Gateway.refund(customer: customer, payment: payment, refund: refund)
        rescue Payments::Errors::ApiError => e
          # Release the reservation only when the gateway explicitly establishes
          # non-execution. An unclassified API error keeps the original operation.
          if AttemptSafety.definitive_rejection?(e)
            refund.mark_failed!(notify: { "error" => "#{e.class}: #{e.message}" })
          end
          raise
        end
        # A TransportError (ambiguous — the PSP may have processed it) intentionally
        # propagates with the row left "requested": the retry path above re-uses it.

        case res[:status]
        when :succeeded
          refund.mark_succeeded!(at: Time.zone.now, psp_refund_id: res[:psp_refund_id],
                                 notify: res[:raw] || {})
        when :processing
          refund.mark_processing!(psp_refund_id: res[:psp_refund_id], notify: res[:raw] || {})
        when :failed
          # Terminal failure from the PSP: record it instead of leaving the
          # refund stranded in `processing` (which the async webhook path,
          # once added, would otherwise be the only way out of).
          refund.mark_failed!(notify: res[:raw] || {})
        end
        refund
      end

      # Guards against over-refunding: only a captured (succeeded) payment may be
      # refunded, the requested amount must be positive, and the cumulative
      # non-failed refunded total must never exceed the captured amount. Runs
      # inside payment.with_lock, and only when creating a genuinely NEW refund
      # row (an in-flight row being reused is not re-validated — it is already
      # counted in `already` below, and re-checking it against itself would
      # make retrying a ceiling-exhausting refund permanently unreachable), so
      # two concurrent NEW partial refunds cannot each pass the ceiling check
      # and jointly exceed the captured amount.
      def self.validate_refundable!(payment, amount)
        if payment.billing_collection?
          raise Payments::Errors::RefundNotAllowed.new(
            "billing collections are settled from Billing, not the payments module",
            code: :billing_collection
          )
        end
        unless payment.status == "succeeded"
          raise Payments::Errors::RefundNotAllowed.new(
            "payment #{payment.out_trade_no} is not captured (status=#{payment.status})",
            code: :not_captured
          )
        end
        if amount.to_d <= 0
          raise Payments::Errors::RefundNotAllowed.new(
            "refund amount must be positive", code: :non_positive
          )
        end

        already = Payments::Refund
                    .where(payment_id: payment.id, status: %w[requested processing succeeded])
                    .sum(:amount)
        if already + amount.to_d > payment.amount
          currency  = payment.payment_order&.currency || "CNY"
          remainder = payment.amount - already
          # Rescale major-unit decimal amount to ISO-4217 minor units before
          # formatting so zero-decimal currencies (JPY, KRW, …) are not
          # displayed 100× too large.
          raise Payments::Errors::RefundNotAllowed.new(
            "refund #{amount} exceeds refundable remainder " \
            "#{remainder} for payment #{payment.out_trade_no}",
            code: :exceeds_remainder,
            details: {
              amount:    format_money(amount, currency),
              remainder: format_money(remainder, currency)
            }
          )
        end
      end

      # Service-layer twin of Payments::Admin::CurrencyFormatting#format_money
      # (which is a component concern this activity cannot include): rescale
      # major-unit decimal amount to ISO-4217 minor units before handing it to
      # Billing::CurrencyResolver.format, so zero-decimal currencies (JPY, KRW,
      # …) are not displayed 100× too large.
      def self.format_money(amount, currency)
        minor_units = Payments::Money.to_iso_minor_units(amount, currency)
        Billing::CurrencyResolver.format(minor_units, currency)
      end
      private_class_method :format_money
    end
  end
end
