# frozen_string_literal: true

FactoryBot.define do
  factory :billing_plan, class: "Billing::Plan" do
    sequence(:code) { |n| "PLAN_#{n}" }
    sequence(:name) { |n| "Plan #{n}" }
    description     { "A test billing plan" }
    amount_usd { 99.00 }
    amount_cny { 699.00 }
    interval        { "monthly" }
    trial_days      { 0 }
    active          { true }
    is_default      { false }
    position        { 0 }

    trait :yearly do
      interval { "yearly" }
    end

    trait :with_trial do
      trial_days { 14 }
    end

    trait :default_plan do
      is_default { true }
      amount_usd { 0 }
      amount_cny { 0 }
      trial_days { 0 }
      after(:create) do |plan|
        Billing::AssignPlanLimits.call(plan: plan, limits: { "page" => 10, "entity" => 5, "member" => 1 })
      end
    end

    trait :inactive do
      active { false }
    end

    trait :free do
      amount_usd { 0 }
      amount_cny { 0 }
    end
  end
end
