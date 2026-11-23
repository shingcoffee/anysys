# frozen_string_literal: true

module Billing
  module Activities
    class ExpireOverdueSubscription
      def self.call(subscription:, at:)
        Result.transaction(subscription) do
          was_live = Subscription::LIVE_STATUSES.include?(subscription.status)
          projection = project_recorded_settlements(subscription)
          next projection if projection
          subscription.reload
          unless Subscription::LIVE_STATUSES.include?(subscription.status)
            Notifier.subscription_cancelled(subscription) if was_live
            next Result.new(status: was_live ? :expired : :unchanged, subscription: subscription)
          end
          deadline = PlanChangePolicy.expiration_at(subscription: subscription, at: at)
          next Result.new(status: :unchanged, subscription: subscription) unless deadline
          change = subscription.pending_plan_change
          if change
            CancelPlanChange.call(subscription: subscription, plan_change: change)
            change.update!(status: "expired")
          end
          # An ambiguous capture is reconciled by B even after termination. No
          # new attempt can be submitted for this ended subscription.
          subscription.update!(status: "expired", ended_at: deadline, cancel_at_period_end: false)
          Notifier.subscription_cancelled(subscription)
          Result.new(status: :expired, subscription: subscription)
        end
      end

      def self.project_recorded_settlements(subscription)
        subscription.invoices.order(:id).each do |invoice|
          if invoice.customer_id != subscription.customer_id
            return Result.new(status: :conflict, subscription: subscription, invoice: invoice, reason: :tenant_mismatch)
          end
          # Draft finalization is local and idempotent. Compute zero/coupon totals
          # before an expiry decision; a lost post-commit enqueue must not strand
          # a free accepted cycle or prevent projection of already-recorded money.
          if invoice.draft? && PlanChangePolicy.accepted_invoice?(invoice: invoice, subscription: subscription)
            FinalizeInvoice.call(invoice: invoice)
            Result.collect_after_commit(invoice) unless invoice.reload.paid?
          end
          payments = Collector.platform_payments(invoice).where(status: "succeeded").order(:id)
          if invoice.paid? && (invoice.entitlements_applied_at || invoice.settlement_review_code.present?)
            payments = payments.where.not(id: invoice.payment_id)
          end
          payments.each do |payment|
            result = MarkInvoicePaid.call(invoice: invoice, payment: payment, source: :gateway)
            return projection_conflict(subscription, result) if result.status == :invalid
          end
          invoice.reload
          next unless invoice.paid? && invoice.entitlements_applied_at.nil? && invoice.settlement_review_code.blank?

          source = invoice.settlement_source
          actor = Authentication::User.unscoped.find_by(id: invoice.settled_by_id) if source == "manual"
          result = MarkInvoicePaid.call(invoice: invoice, payment: invoice.payment, source: source,
            actor: actor, reference: invoice.settlement_reference, note: invoice.settlement_note)
          return projection_conflict(subscription, result) if result.status == :invalid
        end
        nil
      end

      def self.projection_conflict(subscription, result)
        Result.new(status: :conflict, subscription: subscription, invoice: result.invoice, reason: result.reason)
      end
      private_class_method :project_recorded_settlements, :projection_conflict
    end
  end
end
