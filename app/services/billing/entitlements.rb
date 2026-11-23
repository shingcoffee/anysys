# frozen_string_literal: true

module Billing
  module Entitlements
    State = Struct.new(:source, :plan_snapshot, :expires_at, :limits, :reason, keyword_init: true)
    module_function

    def for(customer:, at: Time.current)
      if customer.id == Quota::PLATFORM_OWNER_CUSTOMER_ID
        return state(:platform, {}, nil, Countable::Registry.keys.to_h { |key| [key, PlanLimit::UNLIMITED] })
      end
      subscription = current_subscription(customer: customer, at: at)
      if subscription && %w[active trialing past_due].include?(subscription.status)
        boundary = PlanChangePolicy.period_boundary(subscription)
        if boundary && at < boundary && %w[active trialing].include?(subscription.status)
          return purchased(subscription, subscription.status == "trialing" ? :trial : :purchased, boundary)
        end
        deadline = PlanChangePolicy.access_deadline(subscription) if boundary
        if deadline && at < deadline && !subscription.cancel_at_period_end?
          return purchased(subscription, :grace, deadline)
        end
      end
      fallback
    end

    def current_subscription(customer:, at: Time.current)
      subscription = Subscription.unscoped_by_tenant.where(customer_id: customer.id).live.order(:id).first
      return unless subscription
      subscription unless PlanChangePolicy.expiration_at(subscription: subscription, at: at)
    end

    def fallback
      plan = Plan.default_plan
      unless plan
        # Absence is ordinary before the platform configures billing. Do not
        # create rows on a quota read or freeze signup/core resource creation.
        unless Plan.exists?(is_default: true)
          limits = StandardPlans.starter_limits
          return state(:free, { "code" => "starter-monthly", "name" => I18n.t("comp_billing.standard_plans.starter-monthly.name"),
            "amount_cents" => 0, "interval" => "monthly", "limits" => limits }, nil, limits)
        end
      end
      limits = Countable::Registry.keys.to_h { |key| [key, plan ? plan.limit_for(key) : 0] }
      valid = plan && plan.free? && plan.trial_days.zero? && limits.values.all? { |value| value >= 0 }
      unless valid
        return state(:free, {}, nil, Countable::Registry.keys.to_h { |key| [key, 0] }, :fallback_configuration_invalid)
      end
      state(:free, { "plan_id" => plan.id, "code" => plan.code, "name" => plan.name, "limits" => limits }, nil, limits)
    end

    def purchased(subscription, source, deadline)
      snapshot = subscription.plan_snapshot
      limits = Countable::Registry.keys.to_h { |key| [key, snapshot.fetch("limits", {}).fetch(key, 0)] }
      state(source, snapshot, deadline, limits)
    end

    def state(source, snapshot, deadline, limits, reason = nil)
      State.new(source: source, plan_snapshot: Result.freeze_value(snapshot.deep_dup),
        expires_at: deadline, limits: Result.freeze_value(limits), reason: reason).freeze
    end
  end
end
