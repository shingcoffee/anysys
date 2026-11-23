FactoryBot.define do
  factory :constant do
    sequence(:name) { |n| "Constant #{n}" }
    options { ["Option 1", "Option 2", "Option 3"] }
    customer { nil }

    trait :shared do
      customer { nil }
    end

    trait :customer_specific do
      association :customer
    end

    trait :with_countries do
      name { "Countries" }
      options { ["United States", "Canada", "Mexico", "United Kingdom", "Germany"] }
    end

    trait :with_status do
      name { "Status Types" }
      options { ["Active", "Inactive", "Pending", "Archived"] }
    end

    trait :empty_options do
      options { [] }
    end
  end
end
