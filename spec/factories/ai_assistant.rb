# frozen_string_literal: true

FactoryBot.define do
  factory :ai_assistant_provider_settings, class: "AiAssistant::ProviderSettings" do
    provider { "openai_whisper" }
    api_key { "sk-test" }
    transcribe_active { true }
    generation_active { true }
    config { { model: "whisper-1" }.to_json }
  end

  factory :ai_assistant_conversation, class: "AiAssistant::Conversation" do
    customer
    user { association :user, customer: customer }

    trait :archived do
      archived_at { Time.current }
    end

    trait :titled do
      sequence(:title) { |n| "Chat #{n}" }
    end
  end

  factory :ai_assistant_message, class: "AiAssistant::Message" do
    customer
    conversation { association :ai_assistant_conversation, customer: customer }
    role { "user" }
    body { "Hello" }
    status { "complete" }

    trait :assistant do
      role { "assistant" }
      body { "Hi there." }
    end
  end
end
