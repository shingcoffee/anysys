# frozen_string_literal: true

FactoryBot.define do
  factory :email_message_event, class: "Emails::MessageEvent" do
    association :message, factory: :email_message
    event_type { "open" }
    occurred_at { Time.current }
  end
end
