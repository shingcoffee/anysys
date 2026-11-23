# frozen_string_literal: true

module Billing
  module Admin
    # Customer presentation shares the existing eligibility and route contracts.
    class CustomerSubscriptionComponent < PlanComparisonComponent
      USAGE_KEYS = %w[page entity member].freeze
      METER_BAR_CLASSES = { over: "bg-danger", full: "bg-warning", normal: "bg-accent" }.freeze

      def subscription_price
        billing_amount(current_subscription.amount_cents, current_subscription.currency)
      end

      def monthly_equivalent(plan)
        return I18n.t("common.labels.em_dash") unless catalog_currency?

        cents = plan.price_cents_for(currency)
        cents = Rational(cents, 12).round if plan.interval == "yearly"
        billing_amount(cents, currency)
      end

      def subscription_date
        date = if current_subscription.status.in?(%w[cancelled expired])
                 current_subscription.ended_at
               elsif current_subscription.cancel_at_period_end?
                 current_subscription.current_period_end
               elsif current_subscription.status == "trialing"
                 current_subscription.trial_end
               else
                 current_subscription.current_period_end
               end
        billing_date(date)
      end

      def subscription_date_key
        return "settings_billing.subscription.ended_at" if current_subscription.status.in?(%w[cancelled expired])
        return "settings_billing.subscription.cancellation_date" if current_subscription.cancel_at_period_end?

        case current_subscription.status
        when "trialing" then "settings_billing.subscription.trial_end"
        when "active" then "settings_billing.subscription.renewal_date"
        when "cancelled", "expired" then "settings_billing.subscription.ended_at"
        else "settings_billing.subscription.period_end"
        end
      end

      def review_plan
        fact(plan_review, :plan) || plans.find { |plan| plan.code == fact(plan_review, :plan_code) }
      end

      def review_allowed?
        review_plan.present? && fact(plan_review, :allowed) == true && selectable?(review_plan)
      end

      def form_record = current_subscription || Billing::Subscription.new
      def form_scope = "billing_subscription"

      def outstanding_change?
        fact(pending_plan_change, :status).to_s.in?(%w[awaiting_payment scheduled])
      end

      def coupon_code_value
        coupon_code.nil? ? form_value(:coupon_code) : coupon_code
      end

      def field_errors(field)
        (super + Array(fact(submitted_errors, field))).uniq
      end

      def plan_price(plan)
        catalog_currency? && plan.price_cents_for(currency).zero? ? I18n.t("comp_billing.plan_comparison.free") : formatted_price(plan)
      end

      def plan_trial(plan)
        return I18n.t("common.labels.em_dash") unless !subscription_live? && plan.trial_days.to_i.positive?

        I18n.t("comp_billing.plan_comparison.trial_days_free", days: plan.trial_days)
      end

      def trial_offer?(plan) = !subscription_live? && plan.trial_days.to_i.positive?
      def yearly?(plan) = plan.interval == "yearly"

      def changes_blocked?
        catalog_currency? && subscription_live? && plan_review.nil? &&
          plans.any? { |plan| !current_plan?(plan) && !selectable?(plan) }
      end

      def coupon_card? = subscription_live?
      def manage_card? = can_cancel? || can_resume?
      def coupon_summary? = coupon_benefit.present? || current_subscription&.coupon.present?

      def active_coupon_code
        fact(coupon_benefit, :code).presence || current_subscription&.coupon&.code
      end

      def interval_toggle?
        paid = plans.reject { |plan| catalog_currency? && plan.price_cents_for(currency).zero? }
        paid.map(&:interval).uniq.size > 1
      end

      def default_interval
        (review_plan&.interval || (subscription_live? && current_subscription&.interval)).presence_in(%w[monthly yearly]) || "monthly"
      end

      def enrollment_open?(plan)
        form_value(:plan_code).to_s == plan.code && (form_errors.any? || field_errors(:coupon_code).any?)
      end

      def enrollment_error_unmatched?
        code = form_value(:plan_code).to_s
        code.blank? || plans.none? { |plan| plan.code == code }
      end

      def catalog_free?(plan)
        catalog_currency? && plan.price_cents_for(currency).zero?
      end

      def interval_button_class(interval)
        active = default_interval == interval
        base = "rounded-md px-3 py-1.5 text-body-sm font-medium transition-colors"
        active ? "#{base} bg-surface text-text-primary shadow-xs" : "#{base} text-text-secondary hover:text-text-primary"
      end

      def review_confirm_data
        return {} unless subscription_live?

        {
          controller: "billing-plan-compare",
          action: "submit->billing-plan-compare#confirmSwitch",
          billing_plan_compare_confirm_switch_format_value: I18n.t("settings_billing.subscription.confirm_switch"),
          billing_plan_compare_fallback_plan_label_value: I18n.t("comp_billing.plan_comparison.confirm_switch_fallback_plan"),
          billing_plan_compare_plan_name_param: review_plan.name
        }
      end

      def cancelling?
        subscription_live? && current_subscription.cancel_at_period_end?
      end

      def state_note_key
        return "comp_billing.plan_comparison.cancels_at_period_end" if cancelling?

        status = current_subscription.status
        "settings_billing.subscription.states.#{status}" if status.in?(%w[pending past_due paused cancelled expired])
      end

      def default_method_provider
        key = default_payment_method.provider
        I18n.t("settings_billing.payment_methods.providers.#{key}", default: key.to_s)
      end

      def show_one_time_payment? = one_time_payment.present?
      def one_time_dialog_open? = !!one_time_open

      def subscription_one_time_payment_path
        helpers.admin_settings_billing_subscription_one_time_payment_path(customer_id)
      end

      # One meter per enforced quota. Width is a bounded percentage so an
      # over-limit fallback (e.g. 12 / 10 on the free plan) still renders.
      def usage_meters
        limits = fact(entitlements, :limits)
        enabled_items.select { |item| item.key.in?(USAGE_KEYS) }.map do |item|
          limit = fact(limits, item.key).to_i
          used = fact(usage, item.key)
          unlimited = limit == Billing::PlanLimit::UNLIMITED
          value = I18n.t("settings_billing.subscription.usage_value", used: used || I18n.t("common.labels.em_dash"),
                         limit: unlimited ? I18n.t("comp_billing.plan_comparison.unlimited") : limit)
          { label: item.label, value: value }.merge(meter(used, limit, unlimited))
        end
      end

      private

      def meter(used, limit, unlimited)
        return { percent: nil, state: :normal } if unlimited || !used.is_a?(Numeric) || limit <= 0

        { percent: [(used * 100.0 / limit).round, 100].min, state: meter_state(used, limit) }
      end

      def meter_state(used, limit)
        return :over if used > limit
        return :full if used == limit

        :normal
      end
    end
  end
end
