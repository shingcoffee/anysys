# frozen_string_literal: true

FactoryBot.define do
  factory :platform_announcement do
    sequence(:title) { |n| "Announcement #{n}" }
    body_en { "We will be down for maintenance." }
    body_zh { "系统将进行维护。" }
    severity { "info" }
    status { "draft" }
    audience { "all" }

    trait :published do
      status { "published" }
    end

    trait :draft do
      status { "draft" }
    end

    trait :all_customers do
      audience { "all" }
    end

    trait :selected do
      audience { "selected" }
    end

    trait :info do
      severity { "info" }
    end

    trait :warning do
      severity { "warning" }
    end

    trait :critical do
      severity { "critical" }
    end
  end
end
