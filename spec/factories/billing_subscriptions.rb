# frozen_string_literal: true

FactoryBot.define do
  factory :billing_subscription, class: "Billing::Subscription" do
    customer
    association :plan, factory: :billing_plan
    status               { "active" }
    current_period_start { Time.zone.now }
    current_period_end   { 1.month.from_now }
    cancel_at_period_end { false }
    amount_cents         { 9900 }
    interval             { "monthly" }
    started_at           { Time.zone.now }
    request_key          { SecureRandom.uuid }
    currency             { "USD" }
    billing_anchor_day   { current_period_start.day }
    billing_anchor_month { current_period_start.month }
    plan_snapshot do
      Billing::PlanChangePolicy.snapshot(plan: plan, currency: currency).merge(
        "amount_cents" => amount_cents, "interval" => interval)
    end

    trait :trialing do
      status     { "trialing" }
      trial_end  { 14.days.from_now }
      current_period_end { 14.days.from_now }
    end

    trait :past_due do
      status { "past_due" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :cancelled do
      status       { "cancelled" }
      cancelled_at { Time.zone.now }
      ended_at     { Time.zone.now }
    end

    trait :yearly do
      interval           { "yearly" }
      current_period_end { 1.year.from_now }
    end
  end
end
