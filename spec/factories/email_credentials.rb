# frozen_string_literal: true

FactoryBot.define do
  factory :email_credential, class: "Emails::Credential" do
    host { "smtp.example.com" }
    port { 587 }
    username { "user@example.com" }
    password { "secret123" }
    mode { "sandbox" }
    status { "active" }
    authentication { "plain" }
    enable_starttls { true }
    ssl { false }

    trait :production do
      mode { "production" }
    end

    trait :disabled do
      status { "disabled" }
    end
  end
end
