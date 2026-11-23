# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    customer
    sequence(:key)  { |n| "role_#{n}" }
    sequence(:name) { |n| "Role #{n}" }
    description { "A role" }
    system { false }
    locked_grants { false }

    trait :system do
      system { true }
      locked_grants { true }
    end

    trait :owner do
      key { "owner" }
      name { "Owner" }
      system { true }
      locked_grants { true }
    end

    trait :admin do
      key { "admin" }
      name { "Admin" }
      system { true }
      locked_grants { true }
    end

    trait :member do
      key { "member" }
      name { "Member" }
      system { true }
      locked_grants { true }
    end
  end
end
