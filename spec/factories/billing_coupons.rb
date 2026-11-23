# frozen_string_literal: true

FactoryBot.define do
  factory :billing_coupon, class: "Billing::Coupon" do
    sequence(:code) { |n| "COUPON#{n}" }
    sequence(:name) { |n| "Coupon #{n}" }
    discount_type   { "percent" }
    percent_off     { 20 }
    duration        { "once" }
    times_redeemed  { 0 }
    active          { true }

    trait :fixed do
      discount_type    { "fixed" }
      percent_off      { nil }
      amount_off_cents { 500 }
      currency         { "CNY" }
    end

    trait :repeating do
      duration           { "repeating" }
      duration_in_cycles { 3 }
    end

    trait :forever do
      duration { "forever" }
    end

    trait :exhausted do
      max_redemptions { 1 }
      times_redeemed  { 1 }
    end

    trait :expired do
      redeem_by { 1.day.ago }
    end

    trait :inactive do
      active { false }
    end
  end
end
