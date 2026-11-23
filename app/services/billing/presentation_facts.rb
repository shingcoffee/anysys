# frozen_string_literal: true

module Billing
  # Read-only projections for already-authorized billing records. Commands still
  # revalidate under their own locks; these facts never authorize a charge or
  # reserve a coupon cycle, and never include provider tokens or credentials.
  module PresentationFacts
    module_function

    def reason_key(reason)
      return unless reason
      existing = {
        no_active_subscription: "admin_settings.flash.billing.no_active_subscription",
        coupon_not_found: "admin_settings.flash.coupon_redemptions.not_found",
        already_applied: "admin_settings.flash.coupon_redemptions.already_applied",
        not_redeemable: "admin_settings.flash.coupon_redemptions.not_redeemable"
      }
      key = existing.fetch(reason.to_sym) { "admin_settings.flash.billing.reasons.#{reason}" }
      I18n.exists?(key) ? key : "admin_settings.flash.billing.command_invalid"
    end

    def usage(customer:)
      quota = ::Billing::Quota.for(customer)
      %w[page entity member].to_h { |key| [key, quota.usage(key)] }
    end

    def coupon_benefit(subscription:, pending_change: nil)
      return unless subscription
      redemption = ::Billing::CouponRedemption.where(customer_id: subscription.customer_id,
                                                      billing_subscription_id: subscription.id).first
      return unless redemption

      terms = redemption.terms_snapshot
      maximum = case terms.fetch("duration")
                when "once" then 1
                when "repeating" then terms.fetch("duration_in_cycles")
                when "forever" then nil
                else raise ArgumentError, "Invalid accepted coupon duration"
                end
      remaining = maximum && [maximum - redemption.cycles_used, 0].max
      next_terms = pending_change&.status == "scheduled" ? pending_change.target_snapshot : subscription.plan_snapshot
      reason = if !::Billing::Subscription::LIVE_STATUSES.include?(subscription.status)
                 :subscription_ended
               elsif terms.fetch("discount_type") == "fixed" && terms.fetch("currency") != subscription.currency
                 :currency_mismatch
               elsif remaining == 0
                 :exhausted
               elsif next_terms.fetch("amount_cents").zero?
                 :free_cycle
               end
      reason_key = case reason
                   when nil then "comp_billing.subscription_coupon.eligible_next"
                   when :exhausted then "comp_billing.subscription_coupon.exhausted"
                   when :currency_mismatch then "comp_billing.subscription_coupon.currency_mismatch"
                   when :free_cycle then "comp_billing.subscription_coupon.invoice_count_hint"
                   else reason_key(reason)
                   end
      terms.symbolize_keys.merge(redemption_id: redemption.id, cycles_used: redemption.cycles_used,
                                 remaining_cycles: remaining, eligible: reason.nil?, reason: reason, reason_key: reason_key)
    end

    def subscription_actions(subscription:, pending_change:, at: Time.current)
      boundary = subscription && ::Billing::PlanChangePolicy.period_boundary(subscription)
      can_resume = subscription && %w[active trialing past_due].include?(subscription.status) &&
                   subscription.cancel_at_period_end? && boundary && at < boundary
      can_cancel = subscription && ::Billing::Subscription::LIVE_STATUSES.include?(subscription.status) &&
                   !subscription.cancel_at_period_end? && change_cancellable?(pending_change)
      { can_resume: !!can_resume, can_cancel: !!can_cancel }
    end

    def subscription_recovery(subscription:, invoices:, entitlements:, actions:)
      needs_recovery = invoices.any? || subscription&.status.in?(%w[pending past_due paused cancelled expired]) ||
                       entitlements.source == :grace
      return unless needs_recovery

      grace = if subscription && ::Billing::PlanChangePolicy.period_boundary(subscription) &&
                 (subscription.status.in?(%w[pending past_due]) || entitlements.source == :grace)
                ::Billing::PlanChangePolicy.access_deadline(subscription)
              end
      state_key = "settings_billing.subscription.states.#{subscription&.status}"
      actions.merge(invoices: invoices, grace_deadline: grace,
                    reason_key: I18n.exists?(state_key) ? state_key : "settings_billing.subscription.recovery_hint")
    end

    def change_cancellable?(change)
      return true unless change
      change.invoices.all? do |invoice|
        invoice.customer_id == change.customer_id &&
          (invoice.void? || (%w[draft open uncollectible].include?(invoice.status) && !::Billing::Collector.unresolved?(invoice)))
      end
    end

    def provider_options(customer:, currency:)
      ::Billing::AvailableProviders.call(customer: customer, currency: currency).map do |option|
        compatible = option.fetch(:supported_currencies).include?(currency)
        option.merge(enabled: compatible, currency_compatible: compatible,
                     reason_key: compatible ? nil : "settings_billing.payment_methods.currency_incompatible")
      end
    end

    def can_cancel_immediately?(subscription:)
      ::Billing::Subscription::LIVE_STATUSES.include?(subscription.status)
    end

    def method_readiness(payment_method:, currency:, provider_options:)
      method = payment_method
      descriptor = provider_options.find { |option| option.fetch(:key).to_s == method.provider }
      mandate = method.payments_subscription
      enabled = descriptor && descriptor.fetch(:enabled)
      currencies = if descriptor
                     descriptor.fetch(:supported_currencies)
                   elsif ::Payments::Gateways.keys.map(&:to_s).include?(method.provider)
                     ::Payments::Gateways.for(method.provider).supported_currencies.map(&:upcase)
                   else
                     []
                   end
      compatible = mandate && mandate.currency.to_s.upcase == currency && currencies.include?(currency)
      removed = method.removed? || method.removed_at.present?
      reason = ::Billing::Providers.readiness_reason(payment_method: method)
      if removed
        reason = :method_removed
      elsif method.active?
        if !%w[USD CNY].include?(currency)
          reason = :currency_not_supported
        elsif mandate && mandate.currency.to_s.upcase != currency
          reason = :currency_mismatch
        end
        reason ||= :reauthorization_required if descriptor && !enabled && descriptor[:reason_key]
        reason ||= :provider_unavailable unless enabled
        reason ||= :currency_mismatch unless compatible
      end
      charge_ready = method.active? && !removed && !!enabled && !!compatible && reason.nil?
      reason_key = if charge_ready
                     "settings_billing.payment_methods.readiness.active"
                   elsif removed || !method.active?
                     "settings_billing.payment_methods.readiness.#{removed ? 'removed' : method.status}"
                   else
                     reason_key(reason)
                   end
      { active: method.active? && !removed, removed: removed, enabled: !!enabled,
        currency_compatible: !!compatible, charge_ready: charge_ready, ready: charge_ready,
        default_eligible: charge_ready, reason: reason, reason_key: reason_key }
    end

    def one_time_provider_options(currency:)
      ::Billing::OneTimeProviders.options(currency: currency)
    end

    def invoice_collection(invoice:, owner_actions: false, at: Time.current)
      subscription = invoice.subscription
      matching_tenant = subscription.customer_id == invoice.customer_id
      unresolved = ::Billing::Collector.unresolved?(invoice)
      captured = ::Billing::Collector.platform_payments(invoice).where(status: "succeeded")
                 .where.not(id: invoice.payment_id).exists?
      attempt = invoice.collection_attempts.inflight.order(ordinal: :desc, id: :desc).first
      matching_tenant &&= !attempt || attempt.customer_id == invoice.customer_id
      matching_currency = invoice.currency == subscription.currency
      policy = invoice_policy(invoice)
      recoverable = %w[open uncollectible].include?(invoice.status)
      ended = %w[cancelled expired].include?(subscription.status)
      within_deadline = policy[:deadline] && at <= policy[:deadline]
      off_session_unresolved = invoice.collection_attempts.inflight.where.not(billing_payment_method_id: nil).exists?
      can_pay_one_time = matching_tenant && !captured && !off_session_unresolved && matching_currency && recoverable &&
                         policy[:valid] && invoice.total_cents.positive? && !!within_deadline && !ended
      method = ::Billing::PaymentMethod.where(customer_id: invoice.customer_id).default_method.first
      readiness = if recoverable && policy[:valid] && invoice.total_cents.positive? && policy[:mode] == "gateway"
                    ::Billing::Providers.readiness_reason(payment_method: method, invoice: invoice)
                  end
      reason = if !matching_tenant
                 :tenant_mismatch
               elsif !matching_currency
                 :currency_mismatch
               elsif !policy[:valid] && !invoice.draft?
                 :invoice_policy_invalid
               elsif unresolved
                 :collection_in_flight
               elsif recoverable && (ended || !within_deadline)
                 :request_expired
               else
                 readiness || invoice.failure_code.presence&.to_sym
               end
      state = if invoice.paid?
                "settled"
              elsif invoice.void?
                "stopped"
              elsif invoice.draft?
                "draft"
              elsif !matching_tenant || !matching_currency || !policy[:valid]
                "unavailable"
              elsif captured
                "reconciliation_required"
              elsif unresolved
                attempt&.state == "requires_action" ? "requires_action" : "pending"
              elsif ended || !within_deadline
                "stopped"
              elsif invoice.total_cents.positive? && policy[:mode] == "manual"
                "manual"
              elsif readiness
                "blocked"
              elsif invoice.uncollectible?
                "exhausted"
              else
                invoice.collection_state == "blocked" ? "ready" : invoice.collection_state
              end
      safe = matching_tenant && !unresolved
      can_retry = safe && matching_currency && recoverable && policy[:valid] && !!within_deadline && !ended &&
                  (invoice.total_cents.zero? || (policy[:mode] == "gateway" && readiness.nil?))
      next_attempt = invoice.next_attempt_at if state == "retry_wait" && invoice.next_attempt_at &&
                                                 policy[:deadline] && invoice.next_attempt_at <= policy[:deadline]
      { state: state, recorded_state: invoice.collection_state, recorded_mode: invoice.collection_mode,
        effective_mode: policy[:mode], policy_valid: policy[:valid], deadline: policy[:deadline], next_attempt_at: next_attempt,
        failed_attempts: invoice.attempt_count, unresolved: unresolved, reason: reason,
        reason_key: reason == :invoice_policy_invalid ? "comp_billing.collection.states.unavailable" : reason_key(reason),
        can_retry: !!can_retry, can_mark_paid: !!(owner_actions && safe && recoverable),
        can_void: !!(owner_actions && safe && %w[draft open uncollectible].include?(invoice.status)),
        can_authorize_collection: !!(owner_actions && safe && recoverable && policy[:valid] && matching_currency),
        can_pay_one_time: !!can_pay_one_time }
    end

    def subscription_one_time_payment(subscription:, invoices:, at: Time.current)
      ranked = Array(invoices).sort_by do |invoice|
        rank = case invoice.purpose
               when "initial" then 0
               when "renewal" then 1
               when "proration" then 2
               else 3
               end
        [rank, invoice.due_at || Time.at(0), invoice.id]
      end
      payable = ranked.find { |invoice| invoice_collection(invoice: invoice, at: at)[:can_pay_one_time] }
      if payable
        return {
          kind: :unpaid_invoice, invoice_id: payable.id, invoice_number: payable.number,
          amount_cents: payable.total_cents, currency: payable.currency, period_start: payable.period_start,
          period_end: payable.period_end, due_at: payable.due_at,
          providers: one_time_provider_options(currency: payable.currency)
        }
      end

      return unless subscription && ::Billing::Subscription::LIVE_STATUSES.include?(subscription.status) &&
                    !::Billing::PlanChangePolicy.expiration_at(subscription: subscription, at: at)

      draft = subscription.invoices.where(status: "draft").order(:id).detect do |candidate|
        ::Billing::PlanChangePolicy.accepted_invoice?(invoice: candidate, subscription: subscription)
      end
      if draft
        subtotal = draft.line_items.where(kind: %w[subscription proration]).sum(:amount_cents)
        rate = draft.terms_snapshot["tax_rate_bps"].to_i
        total = [subtotal, 0].max + ([subtotal, 0].max * rate / 10_000)
        if total.positive? && %w[USD CNY].include?(draft.currency)
          kind = draft.purpose == "proration" ? :draft_proration : :draft_initial
          return {
            kind: kind, invoice_id: draft.id, invoice_number: nil, amount_cents: total, currency: draft.currency,
            period_start: draft.period_start, period_end: draft.period_end, due_at: draft.due_at,
            providers: one_time_provider_options(currency: draft.currency)
          }
        end
      end

      if %w[active trialing past_due].include?(subscription.status) && !subscription.cancel_at_period_end?
        boundary = ::Billing::PlanChangePolicy.period_boundary(subscription)
        if boundary && at >= boundary && ::Billing::PlanChangePolicy.renewal_invoice(subscription).nil?
          change = subscription.pending_plan_change
          target = change&.status == "scheduled" ? change.target_snapshot : subscription.plan_snapshot
          base_cents = target["amount_cents"].to_i
          if base_cents.positive? && %w[USD CNY].include?(subscription.currency)
            rate = ::Billing::PlanChangePolicy.settings.tax_rate_bps
            total = base_cents + (base_cents * rate / 10_000)
            reset_anchor = change&.status == "scheduled" && target["interval"] != subscription.interval
            day = reset_anchor ? boundary.day : subscription.billing_anchor_day || boundary.day
            month = reset_anchor ? boundary.month : subscription.billing_anchor_month || boundary.month
            finish = ::Billing::PlanChangePolicy.period_end(boundary, interval: target.fetch("interval"),
              anchor_day: day, anchor_month: month)
            return {
              kind: :renewal, invoice_id: nil, invoice_number: nil, amount_cents: total, currency: subscription.currency,
              period_start: boundary, period_end: finish, due_at: boundary,
              providers: one_time_provider_options(currency: subscription.currency)
            }
          end
        end
      end

      nil
    end

    # +invoices+ must already be scoped to one tenant. Balances stay per
    # currency; they are never converted or summed across currencies.
    def invoice_summary(invoices:)
      unpaid = invoices.where(status: %w[open uncollectible])
      outstanding = unpaid.group(:currency).order(:currency).pluck(:currency, Arel.sql("SUM(total_cents)"), Arel.sql("COUNT(*)"))
                          .map { |currency, cents, count| { currency: currency, total_cents: cents.to_i, count: count } }
      { outstanding: outstanding, unpaid_count: outstanding.sum { |row| row[:count] },
        last_paid: invoices.where(status: "paid").where.not(paid_at: nil).order(paid_at: :desc, id: :desc).first }
    end

    def tab_counts(customer:)
      return { payment_methods: 0, invoices: 0 } unless customer

      {
        payment_methods: ::Billing::PaymentMethod.unscoped_by_tenant
                           .where(customer_id: customer.id, status: %w[pending failed]).count,
        invoices: ::Billing::Invoice.unscoped_by_tenant
                    .where(customer_id: customer.id, status: %w[open uncollectible]).count
      }
    end

    def invoice_policy(invoice)
      # An incomplete or contradictory issued policy is surfaced, never filled
      # from today's settings or an unrelated default method's currency.
      terms = invoice.terms_snapshot
      modes = ::Billing::Settings::COLLECTION_MODES
      valid = terms.is_a?(Hash) && modes.include?(terms["collection_mode"]) &&
              terms["collection_mode"] == invoice.collection_mode && terms["currency"] == invoice.currency &&
              terms["grace_period_days"].is_a?(Integer) && terms["grace_period_days"] >= 0 &&
              %w[USD CNY].include?(invoice.currency) && invoice.due_at.present? &&
              (invoice.collection_override_mode.blank? || modes.include?(invoice.collection_override_mode))
      deadline = invoice.collection_deadline if valid
      { valid: valid && deadline.present?, mode: valid ? invoice.effective_collection_mode : nil, deadline: deadline }
    end

    private_class_method :change_cancellable?, :invoice_policy
  end
end
