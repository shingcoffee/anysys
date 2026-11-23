# frozen_string_literal: true

FactoryBot.define do
  factory :email_template_token, class: "Emails::TemplateToken" do
    label { "Custom field" }
    source_type { Emails::TemplateToken::SOURCE_ENTITY }
    customer
    attribute_slug { "name" }
    # uuid left blank → model assigns SecureRandom.uuid

    after(:build) do |token, _evaluator|
      next if token.entity.present? || token.platform?

      token.entity = create(:entity, :with_name_status_schema, customer: token.customer)
    end

    trait :platform do
      customer { nil }
      entity { nil }
      attribute_slug { nil }
      source_type { Emails::TemplateToken::SOURCE_PLATFORM }
      sequence(:source_key) { |n| "platform_field_#{n}" }
      label { "platform_field" }
    end
  end
end
