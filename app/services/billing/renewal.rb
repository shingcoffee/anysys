# frozen_string_literal: true

module Billing
  module Renewal
    module_function

    def prepare(subscription:, at: Time.current)
      Result.transaction(subscription) do
        next Result.new(status: :ended, subscription: subscription) unless Subscription::LIVE_STATUSES.include?(subscription.status)
        expired = Activities::ExpireOverdueSubscription.call(subscription: subscription, at: at)
        next Result.new(status: :blocked, subscription: subscription, invoice: expired.invoice, reason: expired.reason) if expired.status == :conflict
        next Result.new(status: :ended, subscription: subscription) unless Subscription::LIVE_STATUSES.include?(subscription.status)
        boundary = PlanChangePolicy.period_boundary(subscription)
        next Result.new(status: :not_due, subscription: subscription) unless boundary && at >= boundary
        next Result.new(status: :blocked, subscription: subscription, reason: :subscription_not_renewable) if %w[paused pending].include?(subscription.status)

        existing = PlanChangePolicy.renewal_invoice(subscription)
        next Result.new(status: :invoice_ready, subscription: subscription, invoice: existing) if existing

        change = subscription.pending_plan_change
        if change&.kind == "immediate"
          invoice = change.proration_invoice
          if invoice && PlanChangePolicy.unresolved?(invoice)
            if at >= PlanChangePolicy.grace_deadline(invoice)
              Activities::ExpireOverdueSubscription.call(subscription: subscription, at: at)
              next Result.new(status: :ended, subscription: subscription, invoice: invoice, reason: :change_hold_expired)
            end
            next Result.new(status: :blocked, subscription: subscription, plan_change: change, invoice: invoice, reason: :collection_in_flight)
          end
          cancelled = Activities::CancelPlanChange.call(subscription: subscription, plan_change: change)
          next Result.new(status: :blocked, subscription: subscription, reason: cancelled.reason) if cancelled.status == :conflict
          change.update!(status: "expired")
          change = nil
        end
        target = change&.target_snapshot || subscription.plan_snapshot
        reset_anchor = change && target.fetch("interval") != subscription.interval
        day = reset_anchor ? boundary.day : subscription.billing_anchor_day || boundary.day
        month = reset_anchor ? boundary.month : subscription.billing_anchor_month || boundary.month
        finish = PlanChangePolicy.period_end(boundary, interval: target.fetch("interval"), anchor_day: day, anchor_month: month)
        terms = PlanChangePolicy.invoice_terms(target, due_at: boundary).merge("billing_anchor_day" => day, "billing_anchor_month" => month)
        # A voided frozen scheduled invoice cannot be reused for another target.
        # A revision suffix follows only an explicit cancellation, never a retry.
        key = "renewal:#{subscription.id}:#{boundary.utc.iso8601(6)}"
        voided = subscription.invoices.where(purpose: "renewal", period_start: boundary, status: "void").count
        key += ":revision:#{voided}" if voided.positive?
        invoice = Activities::GenerateInvoice.call(subscription: subscription, purpose: :renewal,
          idempotency_key: key, period_start: boundary, period_end: finish,
          terms_snapshot: terms, plan_change: change)
        Result.new(status: :invoice_ready, subscription: subscription, invoice: invoice, plan_change: change)
      end
    end
  end
end
