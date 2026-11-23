# frozen_string_literal: true

FactoryBot.define do
  factory :captcha_provider_settings, class: "Captcha::ProviderSettings" do
    provider          { "aliyun" }
    access_key_id     { "AKID-test" }
    access_key_secret { "SECRET-test" }
    enabled           { true }
    config do
      {
        scene_id: "1ab23cde",
        prefix: "captcha-test-identity",
        endpoint: "captcha.cn-shanghai.aliyuncs.com",
        region:   "cn-shanghai"
      }.to_json
    end
  end
end
