# frozen_string_literal: true

module Billing
  module Activities
    class Subscribe
      def self.call(customer:, plan:, coupon: nil, request_key:)
        invoice = nil
        recovery_invoice = nil
        rejected = nil
        result = Result.transaction(customer) do
          scope = Subscription.unscoped_by_tenant.where(customer_id: customer.id)
          previous = scope.find_by(request_key: request_key)
          if previous
            accepted_invoice = previous.invoices.find_by(purpose: "initial")
            recovery_invoice = accepted_invoice if Subscription::LIVE_STATUSES.include?(previous.status) && accepted_invoice&.draft?
            next Result.new(status: :unchanged, subscription: previous,
              invoice: accepted_invoice, reason: :request_replayed)
          end
          live = scope.live.first
          if live
            expired = ExpireOverdueSubscription.call(subscription: live, at: Time.current)
            next expired if expired.status == :conflict
            live = nil unless Subscription::LIVE_STATUSES.include?(live.reload.status)
          end
          next Result.new(status: :unchanged, subscription: live, reason: :live_subscription_exists) if live

          currency = CurrencyResolver.for_customer(customer)
          form = Contracts::Subscribe.new(OpenStruct.new)
          unless form.validate(plan_code: plan&.code, coupon_code: coupon&.code, currency: currency, request_key: request_key)
            next Result.invalid(:validation_failed, form: form, errors: form.errors.messages)
          end
          if Entitlements.fallback.reason
            form.errors.add(:base, I18n.t("admin_settings.flash.billing.reasons.fallback_configuration_invalid"))
            next Result.invalid(:fallback_configuration_invalid, form: form, errors: form.errors.messages)
          end
          # Expiry cannot erase uncertain money. Project locally recorded
          # captures through B; an unknown/submitting/SCA historical attempt
          # must reconcile before a new enrollment can prepare another charge.
          conflict = nil
          Billing::Invoice.unscoped_by_tenant.where(customer_id: customer.id).order(:id).each do |old_invoice|
            next unless Collector.unresolved?(old_invoice)
            old_subscription = old_invoice.subscription
            if old_subscription.customer_id != customer.id
              conflict = Result.new(status: :conflict, invoice: old_invoice, reason: :tenant_mismatch)
              break
            end
            projected = ExpireOverdueSubscription.call(subscription: old_subscription, at: Time.current)
            if projected.status == :conflict || Collector.unresolved?(old_invoice.reload)
              conflict = Result.new(status: :conflict, subscription: old_invoice.subscription,
                invoice: old_invoice, reason: projected.reason || :collection_in_flight)
              break
            end
          end
          next conflict if conflict
          now = Time.current
          snapshot = PlanChangePolicy.snapshot(plan: plan.reload, currency: currency)
          trial = snapshot.fetch("amount_cents").positive? && plan.trial_days.positive? && customer.trial_used_at.nil?
          finish = trial ? now + plan.trial_days.days : PlanChangePolicy.period_end(now, interval: plan.interval)
          subscription = scope.create!(billing_plan_id: plan.id, request_key: request_key,
            plan_snapshot: snapshot, amount_cents: snapshot.fetch("amount_cents"), currency: currency,
            interval: plan.interval, status: trial ? "trialing" : "pending", started_at: now,
            trial_end: trial ? finish : nil, current_period_start: now, current_period_end: finish,
            billing_anchor_day: trial ? finish.day : now.day, billing_anchor_month: trial ? finish.month : now.month)
          if coupon
            attached = ApplyCoupon.call(subscription: subscription, coupon: coupon)
            unless %i[applied unchanged].include?(attached.status)
              # Invalid inventory races roll back enrollment, never silently
              # accept a request with the customer's coupon discarded.
              form.errors.add(:coupon_code, I18n.t("admin_settings.errors.validations.coupon_not_redeemable"))
              rejected = Result.invalid(attached.reason, form: form, errors: form.errors.messages)
              raise ActiveRecord::Rollback
            end
          end
          customer.update!(trial_used_at: now) if trial
          unless trial
            invoice = GenerateInvoice.call(subscription: subscription, purpose: :initial,
              idempotency_key: "initial:#{subscription.id}", period_start: now, period_end: finish,
              terms_snapshot: PlanChangePolicy.invoice_terms(snapshot, due_at: now))
          end
          Result.new(status: trial ? :trialing : :awaiting_payment, subscription: subscription, invoice: invoice)
        end
        result ||= rejected
        Result.collect_after_commit(invoice || recovery_invoice) if invoice || recovery_invoice
        return result unless result&.subscription && invoice

        subscription = result.subscription.reload
        Result.new(status: subscription.status == "active" ? :active : :awaiting_payment,
          subscription: subscription, invoice: invoice.reload)
      end
    end
  end
end
