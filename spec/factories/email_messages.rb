# frozen_string_literal: true

FactoryBot.define do
  factory :email_message, class: "Emails::Message" do
    customer
    to { "recipient@example.com" }
    from { "sender@example.com" }
    subject { "Test Email" }
    body_html { "<p>Test content</p>" }
    status { "pending" }
    message_type { "transactional" }
    provider { "smtp" }

    trait :queued do
      status { "queued" }
    end

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failure_code { "SMTP_ERROR" }
      failure_message { "Connection refused" }
    end

    trait :campaign do
      message_type { "campaign" }
      metadata { { send_activity_id: 1, subscriber_id: 1 } }
    end
  end
end
