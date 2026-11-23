# frozen_string_literal: true

FactoryBot.define do
  factory :people_pending_claim, class: "People::PendingClaim" do
    customer
    user { association :user, :member, customer: customer }
    entity_entry { nil }
    continuation { nil }
    created_user { false }
    expires_at { 3.days.from_now }
  end
end
