# frozen_string_literal: true

module Billing
  module Admin
    # Renders a summary card for the customer's current billing subscription,
    # including status badge, next-renewal date, plan details, and action buttons.
    # Used on the customer subscription area (Area a show, Area b show).
    #
    # Constructor:
    #   subscription:   Billing::Subscription or nil
    #   customer_id:    customer_id (string/integer) for building route helpers
    #   show_actions:   bool — whether to render change-plan / cancel / resume buttons
    #                   (true on Area b, false on Area a read-only view)
    class SubscriptionSummaryComponent < ApplicationComponent
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

      def initialize(subscription:, customer_id:, show_actions: false, platform: false,
                     pending_plan_change: nil, coupon_benefit: nil, entitlements: nil, can_cancel_immediately: false,
                     subscription_actions: nil, can_cancel: nil, can_resume: nil)
        @subscription  = subscription
        @customer_id   = customer_id.to_s
        @show_actions  = show_actions
        @subscription_actions, @can_cancel, @can_resume = subscription_actions || {}, can_cancel, can_resume
        @platform, @pending_plan_change, @coupon_benefit, @entitlements, @can_cancel_immediately = platform, pending_plan_change, coupon_benefit, entitlements, can_cancel_immediately
      end

      attr_reader :subscription, :customer_id, :show_actions
      attr_reader :platform, :pending_plan_change, :coupon_benefit, :entitlements, :can_cancel_immediately
      attr_reader :subscription_actions, :can_cancel, :can_resume

      def has_subscription? = subscription.present?

      def status_variant
        STATUS_BADGE_MAP.fetch(subscription&.status.to_s, :default)
      end

      def status_label
        I18n.t("comp_billing.subscription_summary.statuses.#{subscription&.status}")
      end

      def formatted_amount
        return I18n.t("common.labels.em_dash") unless subscription
        billing_amount(subscription.amount_cents, subscription.currency)
      end

      def interval_label
        case subscription&.interval
        when "yearly"  then I18n.t("comp_billing.subscription_summary.interval_year")
        when "monthly" then I18n.t("comp_billing.subscription_summary.interval_month")
        else I18n.t("common.labels.em_dash")
        end
      end

      def next_renewal_label
        return I18n.t("common.labels.em_dash") unless subscription
        return billing_time(subscription.ended_at) if subscription.status.in?(%w[cancelled expired])
        return billing_time(subscription.current_period_end) if subscription.cancel_at_period_end?
        if subscription.status == "trialing"
          date = subscription.trial_end
          return I18n.t("common.labels.em_dash") if date.blank?

          return I18n.t("comp_billing.subscription_summary.trial_ends_date",
                        date: I18n.l(date.to_date, format: :long))
        end
        return I18n.t("common.labels.em_dash") if subscription.current_period_end.blank?

        billing_time(subscription.current_period_end)
      end

      def show_cancel_button?
        show_actions && has_subscription? && (can_cancel.nil? ? fact(subscription_actions, :can_cancel) : can_cancel) == true
      end

      def show_resume_button?
        show_actions && has_subscription? && (can_resume.nil? ? fact(subscription_actions, :can_resume) : can_resume) == true
      end

      def show_change_plan_button?
        show_actions && subscription&.status.in?(%w[trialing active])
      end

      def show_subscribe_button?
        show_actions && !has_subscription?
      end

      def date_key
        return "settings_billing.subscription.ended_at" if subscription.status.in?(%w[cancelled expired])
        return "settings_billing.subscription.cancellation_date" if subscription.cancel_at_period_end?
        return "settings_billing.subscription.trial_end" if subscription.status == "trialing"
        subscription.status == "active" ? "settings_billing.subscription.renewal_date" : "settings_billing.subscription.period_end"
      end

      def period_label
        return I18n.t("common.labels.em_dash") unless subscription&.current_period_start && subscription.current_period_end

        "#{I18n.l(subscription.current_period_start.to_date, format: :long)} – #{I18n.l(subscription.current_period_end.to_date, format: :long)}"
      end

      def customer_name
        subscription.customer.name if subscription.respond_to?(:customer) && subscription.customer.respond_to?(:name)
      end

      def show_immediate_cancel?
        platform && can_cancel_immediately && subscription&.status.in?(%w[pending trialing active past_due paused])
      end

      def cancelling_scheduled?
        has_subscription? && !subscription.status.in?(%w[cancelled expired]) && subscription.cancel_at_period_end?
      end

      def pending_target
        fact(pending_plan_change, :target_snapshot)
      end
    end
  end
end
