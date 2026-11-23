# frozen_string_literal: true

FactoryBot.define do
  factory :speech_to_text_clip, class: "SpeechToText::Clip" do
    customer
    user { association :user, customer: customer }
    field_dom_id { "entity_entry_title" }
    language { "auto" }
    status { "pending" }
    destination { "field" }

    trait :assistant do
      field_dom_id { AiAssistant::AssistantPanelComponent::COMPOSER_ID }
      destination { "assistant" }
    end

    trait :with_audio do
      after(:create) do |clip|
        clip.audio.attach(
          io: StringIO.new("fake-webm-bytes"),
          filename: "clip.webm",
          content_type: "audio/webm"
        )
      end
    end

    trait :succeeded do
      status { "succeeded" }
    end

    trait :failed do
      status { "failed" }
      error_code { "empty" }
    end
  end
end
