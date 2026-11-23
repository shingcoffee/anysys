FactoryBot.define do
  factory :sms_credential, class: "Sms::Credential" do
    provider          { "aliyun" }
    mode              { "sandbox" }
    access_key_id     { "AKID_TEST" }
    access_key_secret { "AKSECRET_TEST" }
    config            { { "sign_name" => "MyApp", "region" => "cn-hangzhou" } }
    status            { "active" }
  end

  factory :sms_template, class: "Sms::Template" do
    sequence(:key) { |n| "verify_code_#{n}" }
    provider_template_codes { { "aliyun" => "SMS_12345678" } }
    description              { "Verification code template" }
    variables                { %w[code minutes] }
    status                   { "active" }
  end

  factory :sms_message, class: "Sms::Message" do
    association :customer
    provider     { "aliyun" }
    to           { "+8613800138000" }
    template_key { "verify_code" }
    vars         { { "code" => "1234", "minutes" => "5" } }
    status       { "pending" }
  end

  factory :sms_opt_out, class: "Sms::OptOut" do
    customer_id { nil }
    provider    { "twilio" }
    phone_e164  { "+8613800138000" }
    reason      { "inbound:STOP" }
  end
end
