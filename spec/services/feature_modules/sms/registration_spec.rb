# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Sms::Registration do
  it_behaves_like "a feature module registration", key: "sms", name: "SMS"

  it "translates the campaign and transactional description at call time across locale switches" do
    %w[en zh-CN en].each do |locale|
      I18n.with_locale(locale) do
        description = described_class.module_description
        expect(description).to eq(I18n.t("sms_campaign_http.registration.description"))
        expect(description).not_to include("Translation missing", "translation missing")
        if locale == "en"
          expect(description).to eq("Audience-based SMS campaigns and transactional messaging via pluggable providers")
        else
          expect(description).to eq("通过可扩展服务商发送定向短信活动与事务短信")
        end
      end
    end
  end
end
