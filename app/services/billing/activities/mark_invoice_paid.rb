# frozen_string_literal: true

module Billing
  module Activities
    class MarkInvoicePaid
      def self.call(invoice:, payment: nil, source:, paid_at: Time.current, actor: nil, reference: nil, note: nil)
        Collector.with_invoice(invoice) do
          source = source.to_s
          reason = validation_reason(invoice, payment, source, actor, reference)
          return Billing::Result.new(status: :invalid, invoice: invoice, reason: reason) if reason
          paid_at = payment.paid_at if source == "gateway"
          if source == "gateway"
            invoice.collection_attempts.find_by!(payment_id: payment.id).update!(state: "succeeded", completed_at: payment.paid_at, claimed_at: nil, reconcile_at: nil)
          end
          if invoice.paid?
            if payment && invoice.payment_id != payment.id
              invoice.update!(settlement_review_code: "duplicate_capture")
              Notifier.settlement_review(invoice, "duplicate_capture", payment_id: payment.id)
              return Billing::Result.new(status: :review_required, invoice: invoice, reason: :duplicate_capture)
            end
            if invoice.entitlements_applied_at.nil? && invoice.settlement_review_code.blank?
              applied = Billing::Activities::ApplyInvoiceSettlement.call(invoice: invoice, paid_at: invoice.paid_at)
              Notifier.payment_succeeded(invoice)
              if applied.status == :review_required
                Notifier.settlement_review(invoice, applied.reason, payment_id: payment&.id)
                return Billing::Result.new(status: :review_required, invoice: invoice, subscription: applied.subscription,
                  plan_change: applied.plan_change, reason: applied.reason)
              end
              return Billing::Result.new(status: :paid, invoice: invoice, subscription: applied.subscription, plan_change: applied.plan_change)
            end
            return Billing::Result.new(status: invoice.settlement_review_code.present? ? :review_required : :unchanged,
              invoice: invoice, subscription: invoice.subscription, reason: invoice.settlement_review_code&.to_sym)
          end
          review = invoice.void? ? "void_capture" : nil
          invoice.update!(status: "paid", paid_at: paid_at, payment_id: payment&.id, settlement_source: source,
            settled_by_id: actor&.id, settlement_reference: reference, settlement_note: note.presence || invoice.settlement_note,
            collection_state: "settled", collection_claimed_at: nil, next_attempt_at: nil, failure_code: nil,
            settlement_review_code: review)
          # A honors persisted review markers, including a void capture. It also
          # expires a pending initial intent rather than granting stale access.
          applied = Billing::Activities::ApplyInvoiceSettlement.call(invoice: invoice, paid_at: paid_at)
          if applied.status == :review_required
            review ||= applied.reason.to_s.presence || "stale_intent"
            invoice.update!(settlement_review_code: review)
          end
          Notifier.payment_succeeded(invoice)
          Notifier.settlement_review(invoice, review, payment_id: payment&.id) if review
          Billing::Result.new(status: review ? :review_required : :paid, invoice: invoice, subscription: applied.subscription,
            plan_change: applied.plan_change, reason: review&.to_sym)
        end
      end

      def self.validation_reason(invoice, payment, source, actor, reference)
        return :invalid_settlement_source unless %w[gateway manual zero].include?(source)
        return :invoice_not_issued if invoice.draft?
        if source == "gateway"
          return :payment_mismatch unless payment && payment.status == "succeeded" && payment.paid_at.present? &&
            payment.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID &&
            payment.payment_order.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID &&
            payment.payment_order.external_ref == "billing-inv-#{invoice.id}" &&
            Payments::Money.new(payment.amount, invoice.currency).smallest_unit == invoice.total_cents &&
            payment.payment_order.currency == invoice.currency
          attempt = invoice.collection_attempts.find_by(payment_id: payment.id)
          return :payment_mismatch unless attempt && attempt.customer_id == invoice.customer_id &&
            attempt.merchant_account_id == payment.merchant_account_id && attempt.request_key == payment.out_trade_no
        elsif source == "manual"
          return :owner_required unless actor&.owner? && actor.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID
          return :settlement_reference_required if reference.blank?
          return :collection_in_flight if Collector.unresolved?(invoice)
          return :invoice_not_payable unless invoice.open? || invoice.uncollectible? || invoice.paid?
        else
          return :not_zero_invoice unless invoice.total_cents.zero? && payment.nil?
          return :invoice_not_payable unless invoice.open? || invoice.paid?
        end
        nil
      end
      private_class_method :validation_reason
    end
  end
end
