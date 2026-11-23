# frozen_string_literal: true

module Billing
  module Notifier
    class << self
      def invoice_issued(invoice) = record("invoice_issued:#{invoice.id}", "invoice_issued", invoice: invoice)
      def payment_succeeded(invoice) = record("invoice_paid:#{invoice.id}", "payment_succeeded", invoice: invoice)
      def payment_failed(invoice, attempt:)
        record("attempt_failed:#{attempt.id}", "payment_failed", invoice: invoice, attempt: attempt)
      end
      def collection_blocked(invoice, reason)
        record("invoice_blocked:#{invoice.id}:#{reason}", "collection_blocked", invoice: invoice)
      end
      def collection_exhausted(invoice) = record("invoice_exhausted:#{invoice.id}", "collection_exhausted", invoice: invoice)
      def collection_authorized(invoice)
        record("invoice_authorized:#{invoice.id}:#{invoice.collection_override_at.utc.iso8601(6)}", "collection_authorized", invoice: invoice)
      end
      def settlement_review(invoice, code, payment_id: nil)
        record("settlement_review:#{invoice.id}:#{code}:#{payment_id}", "settlement_review", invoice: invoice)
      end
      def trial_ending(subscription)
        record("trial_ending:#{subscription.id}:#{subscription.trial_end.utc.iso8601(6)}", "trial_ending", subscription: subscription)
      end
      def subscription_cancelled(subscription)
        time = subscription.ended_at || subscription.cancelled_at || subscription.current_period_end
        record("subscription_cancelled:#{subscription.id}:#{time&.utc&.iso8601(6)}", "subscription_cancelled", subscription: subscription)
      end
      def subscription_past_due(subscription)
        record("subscription_past_due:#{subscription.id}:#{subscription.past_due_at.utc.iso8601(6)}", "subscription_past_due", subscription: subscription)
      end

      private

      def record(key, kind, invoice: nil, subscription: nil, attempt: nil)
        subscription ||= invoice&.subscription
        scope = Notice.unscoped_by_tenant.where(event_key: key)
        scope.first || scope.create!(customer_id: subscription.customer_id, kind: kind, state: "pending",
          billing_invoice_id: invoice&.id, billing_subscription_id: subscription.id, billing_collection_attempt_id: attempt&.id)
      rescue ActiveRecord::RecordNotUnique
        scope.first!
      end
    end
  end
end
