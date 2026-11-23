# frozen_string_literal: true

FactoryBot.define do
  factory :billing_invoice, class: "Billing::Invoice" do
    customer
    subscription { association(:billing_subscription, customer: customer) }
    purpose { "renewal" }
    sequence(:idempotency_key) { |n| "test-invoice:#{n}" }
    collection_state { "ready" }
    collection_mode { "gateway" }
    terms_snapshot do
      { "plan_id" => subscription.billing_plan_id, "name" => subscription.plan.name, "code" => subscription.plan.code,
        "amount_cents" => subscription.amount_cents, "currency" => currency, "interval" => subscription.interval,
        "limits" => {}, "collection_mode" => collection_mode, "tax_rate_bps" => 0,
        "grace_period_days" => 14, "dunning_schedule" => [1, 3, 7],
        "billing_anchor_day" => period_start.day, "billing_anchor_month" => period_start.month, "due_at" => (due_at || period_start).iso8601(6) }
    end
    status          { "draft" }
    period_start    { Time.zone.now - 1.month }
    period_end      { Time.zone.now }
    subtotal_cents  { 0 }
    discount_cents  { 0 }
    tax_cents       { 0 }
    total_cents     { 0 }
    currency        { subscription.currency }
    attempt_count   { 0 }

    trait :open do
      status    { "open" }
      sequence(:number) { |n| "INV-TEST-#{n.to_s.rjust(5, '0')}" }
      issued_at { Time.zone.now }
      due_at    { Time.zone.now }
    end

    trait :paid do
      status  { "paid" }
      collection_state { "settled" }
      paid_at { Time.zone.now }
    end

    trait :void do
      status { "void" }
    end
  end
end
