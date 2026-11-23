# frozen_string_literal: true

FactoryBot.define do
  sequence(:sms_audience_phone) { |n| "+86138#{format('%08d', n)}" }

  factory :sms_contact, class: "Sms::Contact" do
    customer
    phone_e164 { generate(:sms_audience_phone) }
    name { "Alice" }
    country_code { "CN" }
    timezone { "Asia/Shanghai" }
    trait(:granted) { consent_status { "granted" } }
    trait(:archived) { status { "archived" } }
  end

  factory :sms_consent_event, class: "Sms::ConsentEvent" do
    contact { association :sms_contact }
    customer { contact.customer }
    phone_e164 { contact.phone_e164 }
    action { "revoked" }
    source { "provider_opt_out" }
    occurred_at { 1.hour.ago }
    evidence { { "provider" => "twilio", "code" => "21610" } }
    sequence(:event_key) { |n| "provider-event-#{n}" }
  end

  factory :sms_segment, class: "Sms::Audience::Segment" do
    customer
    sequence(:name) { |n| "Audience #{n}" }
    segment_rules { {} }
  end

  factory :sms_campaign, class: "Sms::Campaign" do
    customer
    sequence(:name) { |n| "Campaign #{n}" }
    created_by { association :user, :admin, customer: customer }
  end

  factory :sms_campaign_recipient, class: "Sms::CampaignRecipient" do
    campaign { association :sms_campaign }
    customer { campaign.customer }
    contact { association :sms_contact, customer: customer }
    phone_e164 { contact.phone_e164 }
    contact_snapshot { { "phone_e164" => phone_e164, "eligibility_at_start" => { "eligible" => false, "reason" => "consent_missing" } } }
  end
end
