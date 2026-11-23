# frozen_string_literal: true

module Billing
  module PlanChangePolicy
    PLAN_KEYS = %w[plan_id code name amount_cents currency interval limits grace_period_days].freeze
    REQUEST_KEY = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    module_function

    def snapshot(plan:, currency:)
      {
        "plan_id" => plan.id, "code" => plan.code, "name" => plan.name,
        "amount_cents" => plan.price_cents_for(currency), "currency" => currency,
        "interval" => plan.interval,
        "limits" => Countable::Registry.keys.to_h { |key| [key, plan.limit_for(key)] },
        "grace_period_days" => settings.grace_period_days
      }
    end

    def settings
      # Command defaults are explicit; queries never create the singleton.
      Settings.find_by(singleton_guard: 0) || Settings.new(
        collection_mode: "manual", tax_rate_bps: 0, grace_period_days: 7,
        trial_ending_notice_days: 3, dunning_schedule: [1, 3, 7])
    end

    def invoice_terms(snapshot, due_at:)
      policy = settings
      snapshot.deep_dup.merge(
        "tax_rate_bps" => policy.tax_rate_bps,
        "collection_mode" => policy.collection_mode,
        "dunning_schedule" => Array(policy.dunning_schedule),
        "grace_period_days" => policy.grace_period_days,
        "due_at" => due_at.iso8601(6))
    end

    def period_end(time, interval:, anchor_day: time.day, anchor_month: time.month)
      candidate = case interval
      when "monthly" then time + 1.month
      when "yearly" then (time + 1.year).change(month: anchor_month)
      else raise ArgumentError, "Unsupported billing interval"
      end
      candidate.change(day: [anchor_day, candidate.end_of_month.day].min)
    end

    def preview(subscription:, new_plan:, at: Time.current)
      reason = rejection(subscription, new_plan, at)
      kind = if subscription.status == "trialing" || subscription.interval != new_plan.interval ||
          new_plan.price_cents_for(subscription.currency) <= subscription.amount_cents
        :scheduled
      else
        :immediate
      end if %w[USD CNY].include?(subscription.currency)
      subtotal = if reason || kind != :immediate
        0
      else
        Proration.credit_and_charge(subscription: subscription, new_plan: new_plan, at: at).sum { |line| line[:amount_cents] }
      end
      tax = subtotal * settings.tax_rate_bps / 10_000
      { kind: kind, effective_at: kind == :immediate ? at : period_boundary(subscription),
        currency: subscription.currency, subtotal_cents: subtotal, tax_cents: tax,
        total_cents: subtotal + tax, reason: reason, allowed: reason.nil? }
    end

    def rejection(subscription, plan, at)
      return :plan_not_active unless plan.active? && plan.archived_at.nil?
      return :currency_not_supported unless %w[USD CNY].include?(subscription.currency)
      return :change_requires_active_subscription unless %w[active trialing].include?(subscription.status)
      return :cancellation_scheduled if subscription.cancel_at_period_end?
      boundary = period_boundary(subscription)
      return :renewal_due unless boundary && at < boundary
      return :pending_change_exists if subscription.pending_plan_change
      return :unchanged if subscription.billing_plan_id == plan.id
    end

    def grace_deadline(invoice)
      due = invoice.due_at || Time.iso8601(invoice.terms_snapshot.fetch("due_at"))
      due + invoice.terms_snapshot.fetch("grace_period_days", 0).to_i.days
    end

    # Access grace and collection lifetime are different policies. Zero grace
    # means no unpaid service, not an impossible instantaneous PSP timestamp.
    # Keep accepted initial/renewal requests recoverable through their fixed
    # period end; proration holds retain their ordinary boundary grace.
    def request_deadline(invoice)
      if invoice.terms_snapshot.fetch("grace_period_days", 0).to_i.zero? && %w[initial renewal].include?(invoice.purpose)
        invoice.period_end
      else
        grace_deadline(invoice)
      end
    end

    def renewal_invoice(subscription)
      subscription.invoices.where(purpose: "renewal", period_start: period_boundary(subscription))
        .where.not(status: "void").order(:id).first
    end

    def access_deadline(subscription)
      invoice = if subscription.status == "pending"
        subscription.invoices.find_by(purpose: "initial")
      else
        renewal_invoice(subscription)
      end
      if !invoice && subscription.pending_plan_change&.kind == "immediate"
        invoice = subscription.pending_plan_change.proration_invoice
      end
      return grace_deadline(invoice) if invoice

      boundary = period_boundary(subscription)
      boundary && boundary + subscription.plan_snapshot.fetch("grace_period_days", 0).to_i.days
    end

    def period_boundary(subscription)
      trial = subscription.trial_end
      if trial && subscription.current_period_start && subscription.current_period_start < trial
        trial
      else
        subscription.current_period_end
      end
    end

    # Pure eligibility shared by GET projections and write-side revalidation.
    # Free fallback is NOT itself an ended intent: valid pending/paused rows and
    # renewable overdue rows within their accepted grace remain current.
    def expiration_at(subscription:, at: Time.current)
      return unless Subscription::LIVE_STATUSES.include?(subscription.status)
      if subscription.status == "pending"
        initial = subscription.invoices.find_by(purpose: "initial")
        return initial.updated_at if initial&.void? && at >= initial.updated_at
      end
      boundary = period_boundary(subscription)
      return boundary if subscription.cancel_at_period_end? && boundary && at >= boundary

      deadline = access_deadline(subscription)
      invoice = subscription.status == "pending" ? initial : renewal_invoice(subscription)
      if invoice
        deadline = request_deadline(invoice)
      elsif %w[active trialing past_due].include?(subscription.status) &&
          subscription.plan_snapshot.fetch("grace_period_days", 0).to_i.zero? && subscription.pending_plan_change&.kind != "immediate"
        # A late scheduler must still be able to prepare the next zero-grace
        # renewal. No period is advanced and Entitlements grants no unpaid access.
        change = subscription.pending_plan_change
        target = change&.status == "scheduled" ? change.target_snapshot : subscription.plan_snapshot
        reset = target.fetch("interval") != subscription.interval
        deadline = period_end(boundary, interval: target.fetch("interval"),
          anchor_day: reset ? boundary.day : subscription.billing_anchor_day || boundary.day,
          anchor_month: reset ? boundary.month : subscription.billing_anchor_month || boundary.month) if boundary
      end
      return unless deadline && at >= deadline
      deadline
    end

    def unresolved?(invoice)
      Billing::Collector.unresolved?(invoice)
    end

    # A draft is durable work only while it still corresponds to its persisted
    # acceptance. History, superseded periods and cancelled targets are not new
    # collection authorizations, even if their parent remains a live row.
    def accepted_invoice?(invoice:, subscription:)
      return false unless invoice.customer_id == subscription.customer_id && invoice.billing_subscription_id == subscription.id
      return false unless invoice.currency == subscription.currency
      change = invoice.plan_change
      return false if change && (change.customer_id != subscription.customer_id || change.billing_subscription_id != subscription.id ||
        !%w[awaiting_payment scheduled].include?(change.status))

      case invoice.purpose
      when "initial"
        subscription.status == "pending" && invoice.period_start == subscription.current_period_start && invoice.period_end == subscription.current_period_end
      when "renewal"
        %w[active trialing past_due].include?(subscription.status) && invoice.period_start == period_boundary(subscription)
      when "proration"
        change&.status == "awaiting_payment" && change.period_start == subscription.current_period_start &&
          change.period_end == subscription.current_period_end && invoice.period_start == change.period_start &&
          invoice.period_end == change.period_end && change.from_snapshot == subscription.plan_snapshot
      else
        false
      end
    end

    def outcome(subscription, change)
      status = { "awaiting_payment" => :awaiting_payment, "scheduled" => :scheduled, "applied" => :applied }.fetch(change.status, :unchanged)
      Result.new(status: status, subscription: subscription, plan_change: change,
        invoice: change.proration_invoice, reason: change.status.to_sym)
    end
  end
end
