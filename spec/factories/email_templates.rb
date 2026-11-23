# frozen_string_literal: true

FactoryBot.define do
  factory :email_template, class: "Emails::Template" do
    customer
    name { "Welcome Email" }
    subject {
      token = Emails::TemplateToken.platform.find_by(source_key: "authentication_user.first_name") ||
              Emails::TemplateToken.platform.find_by(source_key: "first_name") ||
              Emails::TemplateToken.create!(source_type: Emails::TemplateToken::SOURCE_PLATFORM, source_key: "authentication_user.first_name", label: "First name")
      "Welcome {{#{token.uuid}}}!"
    }
    body_html {
      token = Emails::TemplateToken.platform.find_by(source_key: "authentication_user.first_name") ||
              Emails::TemplateToken.platform.find_by(source_key: "first_name") ||
              Emails::TemplateToken.create!(source_type: Emails::TemplateToken::SOURCE_PLATFORM, source_key: "authentication_user.first_name", label: "First name")
      "<p>Hello {{#{token.uuid}}}, welcome to our service.</p>"
    }
    editor_type { "code" }
    status { "active" }

    trait :draft do
      status { "draft" }
    end

    trait :rich_text do
      editor_type { "rich_text" }
      body_html { nil }
    end
  end
end
