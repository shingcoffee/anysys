# frozen_string_literal: true

module Billing
  module Activities
    class ChangePlan
      def self.call(subscription:, new_plan:, request_key:)
        invoice = nil
        recovery_invoice = nil
        result = Result.transaction(subscription) do
          previous = PlanChange.unscoped_by_tenant.find_by(customer_id: subscription.customer_id, request_key: request_key)
          if previous
            next Result.new(status: :conflict, subscription: subscription, reason: :request_key_used) if previous.billing_subscription_id != subscription.id
            recovery_invoice = previous.proration_invoice if previous.status == "awaiting_payment" && previous.proration_invoice&.draft?
            next PlanChangePolicy.outcome(subscription, previous)
          end
          pending = subscription.pending_plan_change
          if pending
            if pending.to_plan_id == new_plan.id
              recovery_invoice = pending.proration_invoice if pending.proration_invoice&.draft?
              next PlanChangePolicy.outcome(subscription, pending)
            end
            next Result.new(status: :conflict, subscription: subscription, plan_change: pending, reason: :pending_change_exists)
          end
          next Result.new(status: :unchanged, subscription: subscription) if subscription.billing_plan_id == new_plan.id

          form = Contracts::ChangePlan.new(OpenStruct.new)
          unless form.validate(plan_code: new_plan.code, request_key: request_key)
            next Result.invalid(:validation_failed, subscription: subscription, form: form, errors: form.errors.messages)
          end
          now = Time.current
          preview = PlanChangePolicy.preview(subscription: subscription, new_plan: new_plan.reload, at: now)
          next Result.invalid(preview[:reason], subscription: subscription) unless preview[:allowed]

          change = subscription.plan_changes.create!(customer_id: subscription.customer_id,
            from_plan_id: subscription.billing_plan_id, to_plan_id: new_plan.id, request_key: request_key,
            kind: preview[:kind].to_s, status: preview[:kind] == :immediate ? "awaiting_payment" : "scheduled",
            effective_at: preview[:effective_at], period_start: subscription.current_period_start,
            period_end: subscription.current_period_end, from_snapshot: subscription.plan_snapshot,
            target_snapshot: PlanChangePolicy.snapshot(plan: new_plan, currency: subscription.currency))
          if change.kind == "immediate"
            invoice = GenerateInvoice.call(subscription: subscription, purpose: :proration,
              idempotency_key: "plan-change:#{change.id}", period_start: change.period_start,
              period_end: change.period_end, terms_snapshot: PlanChangePolicy.invoice_terms(change.target_snapshot, due_at: change.period_end),
              plan_change: change, extra_line_items: Proration.credit_and_charge(subscription: subscription, new_plan: new_plan, at: now))
            # Source-period dates correlate the intent; its request expiry is
            # the boundary, not the beginning of already-purchased service.
            invoice.update!(due_at: change.period_end)
          end
          PlanChangePolicy.outcome(subscription, change)
        end
        Result.collect_after_commit(invoice || recovery_invoice) if invoice || recovery_invoice
        invoice ? PlanChangePolicy.outcome(subscription.reload, result.plan_change.reload) : result
      end
    end
  end
end
