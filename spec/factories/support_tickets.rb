# frozen_string_literal: true

FactoryBot.define do
  factory :support_ticket do
    customer
    user { association :user, :admin, customer: customer }
    sequence(:subject) { |n| "Support ticket #{n}" }
    status { "open" }
    last_message_at { Time.current }

    trait :resolved do
      status { "resolved" }
    end

    trait :with_message do
      after(:create) do |request|
        create(:support_ticket_message, support_ticket: request, user: request.user, author_role: "requester")
      end
    end
  end

  factory :support_ticket_message do
    support_ticket
    customer { support_ticket.customer }
    user { support_ticket.user }
    author_role { "requester" }
    body { "Need help with this screen." }

    trait :from_owner do
      author_role { "owner" }
    end
  end
end
