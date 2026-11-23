# frozen_string_literal: true

module Billing
  module Activities
    class ApplyInvoiceSettlement
      # Called INSIDE B's subscription -> invoice settlement transaction. Never
      # commit entitlements independently from the paid financial record.
      def self.call(invoice:, paid_at:)
        raise ArgumentError, "Settlement transaction required" unless ApplicationRecord.connection.transaction_open?
        subscription = Subscription.unscoped_by_tenant.find(invoice.billing_subscription_id)
        unless invoice.status == "paid" && invoice.customer_id == subscription.customer_id && invoice.currency == subscription.currency
          return review(invoice, subscription, :settlement_identity_mismatch)
        end
        if invoice.entitlements_applied_at
          return Result.new(status: :unchanged, subscription: subscription, invoice: invoice)
        end
        if invoice.settlement_review_code.present?
          if invoice.purpose == "initial" && subscription.status == "pending"
            subscription.update!(status: "expired", ended_at: paid_at, cancel_at_period_end: false)
          end
          return review(invoice, subscription, invoice.settlement_review_code.to_sym)
        end
        unless Subscription::LIVE_STATUSES.include?(subscription.status)
          return review(invoice, subscription, :subscription_ended)
        end
        boundary = PlanChangePolicy.period_boundary(subscription)
        if subscription.cancel_at_period_end? && paid_at >= boundary
          subscription.update!(status: "expired", ended_at: boundary, cancel_at_period_end: false)
          return review(invoice, subscription, :cancellation_boundary)
        end
        terms = invoice.terms_snapshot.slice(*PlanChangePolicy::PLAN_KEYS)
        change = invoice.billing_plan_change_id && subscription.plan_changes.find_by(id: invoice.billing_plan_change_id)
        if change && !%w[awaiting_payment scheduled].include?(change.status)
          return review(invoice, subscription, :plan_change_ended)
        end
        invalid_intent = case invoice.purpose
        when "initial"
          :stale_initial unless subscription.status == "pending" && invoice.period_start == subscription.current_period_start && invoice.period_end == subscription.current_period_end
        when "proration"
          :stale_plan_change unless change&.status == "awaiting_payment" && change.period_start == subscription.current_period_start &&
            change.period_end == subscription.current_period_end && subscription.plan_snapshot == change.from_snapshot
        when "renewal"
          :stale_renewal unless invoice.period_start == boundary && %w[active trialing past_due].include?(subscription.status)
        else :unknown_invoice_purpose
        end
        return review(invoice, subscription, invalid_intent) if invalid_intent
        deadline = PlanChangePolicy.request_deadline(invoice)
        zero_cycle = invoice.total_cents.zero? && invoice.settlement_source == "zero" && %w[initial renewal].include?(invoice.purpose)
        if paid_at > deadline && !zero_cycle
          change&.update!(status: "expired")
          subscription.update!(status: "expired", ended_at: deadline, cancel_at_period_end: false)
          return review(invoice, subscription, :settlement_after_expiry)
        end
        recovered = subscription.status == "past_due"
        case invoice.purpose
        when "initial"
          subscription.update!(status: "active", past_due_at: nil)
        when "proration"
          # During the bounded reconciliation hold the boundary is retained.
          # Renewal then starts at that original boundary, not at late capture.
          apply_terms(subscription, change.target_snapshot)
          change.update!(status: "applied", applied_at: paid_at)
        when "renewal"
          apply_terms(subscription, terms)
          subscription.update!(status: "active", current_period_start: invoice.period_start, current_period_end: invoice.period_end,
            billing_anchor_day: invoice.terms_snapshot.fetch("billing_anchor_day"),
            billing_anchor_month: invoice.terms_snapshot.fetch("billing_anchor_month"))
          change&.update!(status: "applied", applied_at: paid_at)
          outstanding = subscription.invoices.where(purpose: "renewal", status: %w[open uncollectible]).where.not(id: invoice.id).order(:due_at).first
          subscription.update!(status: outstanding ? "past_due" : "active", past_due_at: outstanding&.due_at)
        end
        invoice.update!(entitlements_applied_at: paid_at)
        Result.new(status: recovered && invoice.purpose == "renewal" && subscription.status == "active" ? :recovered : :applied,
          subscription: subscription, invoice: invoice, plan_change: change)
      end

      def self.apply_terms(subscription, terms)
        subscription.update!(billing_plan_id: terms.fetch("plan_id"), plan_snapshot: terms,
          amount_cents: terms.fetch("amount_cents"), interval: terms.fetch("interval"))
      end

      def self.review(invoice, subscription, reason)
        invoice.update!(settlement_review_code: reason.to_s)
        Result.new(status: :review_required, subscription: subscription, invoice: invoice, reason: reason)
      end
      private_class_method :apply_terms, :review
    end
  end
end
