FactoryBot.define do
  factory :customer do
    sequence(:name) { |n| "Customer #{n}" }
    # Using add_attribute because 'alias' is a Ruby reserved keyword
    add_attribute(:alias) { nil }
    address { nil }
    contact { nil }
    phone { nil }
    industry { :technology }
    tier { :basic }
    role { :owner }

    trait :with_details do
      add_attribute(:alias) { "Alias" }
      address { "123 Main St" }
      contact { "John Doe" }
      phone { "555-1234" }
      industry { :technology }
    end

    trait :standard do
      tier { :standard }
    end

    trait :premium do
      tier { :premium }
    end

    trait :enterprise do
      tier { :enterprise }
    end

    trait :owner do
      role { :owner }
    end

    trait :admin_role do
      role { :admin }
    end

    trait :member do
      role { :member }
    end
  end
end
