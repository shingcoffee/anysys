# frozen_string_literal: true

FactoryBot.define do
  factory :captcha_url_throttle, class: "Captcha::UrlThrottle" do
    match_kind { "template" }
    sequence(:url_pattern) { |n| "/auth/custom-#{n}" }
    limit_count { 100 }
    period_seconds { 300 }
    every_hit { false }
    skipped { false }
  end
end
