# frozen_string_literal: true

module Billing
  module Admin
    # Renders the compare-mode plan grid for the customer self-service billing
    # settings page (Area b — /:cid/admin/settings/billing/subscription).
    #
    # The wrapper forwards billing query facts to the existing customer surface.
    # Its contained comparison table is shared across viewport sizes.
    #
    # Includes:
    #   - Per-plan price row (localized via CurrencyResolver)
    #   - One limit row per enabled CountableItem ("Unlimited" when not set)
    #   - Trial info row
    #   - Current-plan highlight (badge + distinct styling)
    #   - Server-rendered review and stable request-key submission
    #   - Inline coupon-redemption form
    #   - Cancel / uncancel control for the current subscription
    #
    # Constructor:
    #   plans:                Array/relation of active Billing::Plan records
    #   current_subscription: Billing::Subscription or nil
    #   enabled_items:        Array/relation of enabled Billing::CountableItem records
    #   currency:             "USD" or "CNY" — resolved for the current customer
    #   customer_id:          String/Integer — for route helpers
    class PlanComparisonComponent < ApplicationComponent
      include Presentation
      STATUS_BADGE_MAP = {
        "pending"   => :warning,
        "trialing"  => :info,
        "active"    => :success,
        "past_due"  => :danger,
        "paused"    => :warning,
        "cancelled" => :default,
        "expired"   => :default
      }.freeze

      def initialize(plans:, current_subscription:, enabled_items:, currency:, customer_id:, customer_settings: false,
                     latest_subscription: nil, entitlements: nil, usage: {}, pending_plan_change: nil,
                     plan_review: nil, coupon_benefit: nil, recovery: nil, form: nil, request_key: nil,
                     coupon_code: nil, errors: {}, subscription_actions: nil, can_cancel: nil, can_resume: nil,
                     default_payment_method: nil, one_time_payment: nil, one_time_open: false, one_time_error: nil)
        @plans                = Array(plans)
        @current_subscription = current_subscription
        @enabled_items        = Array(enabled_items)
        @currency             = (current_subscription ? current_subscription.currency : currency).to_s.upcase
        @customer_id          = customer_id.to_s
        @customer_settings    = customer_settings
        @latest_subscription, @entitlements, @usage = latest_subscription, entitlements, usage || {}
        @pending_plan_change, @plan_review, @coupon_benefit, @recovery = pending_plan_change, plan_review, coupon_benefit, recovery
        @form = form
        @coupon_code, @submitted_errors = coupon_code, errors || {}
        @subscription_actions, @can_cancel, @can_resume = subscription_actions || {}, can_cancel, can_resume
        @default_payment_method = default_payment_method
        @one_time_payment, @one_time_open, @one_time_error = one_time_payment, one_time_open, one_time_error
        @request_key = request_key.presence || form_value(:request_key).presence || SecureRandom.uuid
      end

      attr_reader :plans, :current_subscription, :enabled_items, :currency, :customer_id, :customer_settings
      attr_reader :latest_subscription, :entitlements, :usage, :pending_plan_change, :plan_review, :coupon_benefit, :recovery, :form, :request_key
      attr_reader :coupon_code, :submitted_errors
      attr_reader :subscription_actions, :can_cancel, :can_resume, :default_payment_method
      attr_reader :one_time_payment, :one_time_open, :one_time_error

      # ---- subscription helpers ----

      def has_subscription? = current_subscription.present?

      def current_plan_code
        fact(fact(current_subscription, :plan_snapshot), :code).presence || current_subscription&.plan&.code
      end

      def current_plan?(plan)
        subscription_live? && current_plan_code.present? && plan.code == current_plan_code
      end

      def subscription_live?
        current_subscription&.status&.in?(%w[pending trialing active past_due paused])
      end

      def can_cancel?
        has_subscription? && (can_cancel.nil? ? fact(subscription_actions, :can_cancel) : can_cancel) == true
      end

      def can_resume?
        has_subscription? && (can_resume.nil? ? fact(subscription_actions, :can_resume) : can_resume) == true
      end

      def status_variant
        STATUS_BADGE_MAP.fetch(current_subscription&.status.to_s, :default)
      end

      def status_label
        I18n.t("comp_billing.plan_comparison.statuses.#{current_subscription&.status}")
      end

      # Returns the raw renewal/trial date string only (the surrounding sentence
      # is composed by the caller via I18n so it can be localized correctly).
      def renewal_label
        return I18n.t("common.labels.em_dash") unless current_subscription
        date = if current_subscription.status == "trialing"
                 current_subscription.trial_end
               else
                 current_subscription.current_period_end
               end
        date.present? ? I18n.l(date.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      # ---- price helpers ----

      def formatted_price(plan)
        return I18n.t("common.labels.em_dash") unless catalog_currency?

        cents = plan.price_cents_for(currency)
        billing_amount(cents, currency)
      end

      def catalog_currency? = currency.in?(%w[USD CNY])

      def selectable?(plan)
        resolved_change = pending_plan_change.nil? || fact(pending_plan_change, :status).to_s.in?(%w[applied cancelled expired])
        catalog_currency? && !current_plan?(plan) && resolved_change &&
          (!subscription_live? || (current_subscription.status.in?(%w[active trialing]) && !current_subscription.cancel_at_period_end?))
      end

      def review_path(plan)
        helpers.plan_change_preview_admin_settings_billing_subscription_path(customer_id, plan_code: plan.code, locale: I18n.locale, anchor: "plan-review")
      end

      def interval_label(plan)
        plan.interval == "yearly" ? I18n.t("comp_billing.plan_comparison.interval_year") : I18n.t("comp_billing.plan_comparison.interval_month")
      end

      # ---- limit helpers ----

      def limit_display(plan, item)
        val = plan.limit_for(item.key)
        val = 0 if val.nil?
        val == Billing::PlanLimit::UNLIMITED ? I18n.t("comp_billing.plan_comparison.unlimited") : val.to_s
      end

      def unlimited?(plan, item)
        plan.limit_for(item.key) == Billing::PlanLimit::UNLIMITED
      end
    end
  end
end
