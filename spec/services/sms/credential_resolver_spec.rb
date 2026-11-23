# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::CredentialResolver do
  describe ".call" do
    context "with an explicit provider" do
      it "returns the active credential for that provider + mode" do
        cred = create(:sms_credential, provider: "aliyun", mode: "sandbox", status: "active")
        result = described_class.call(mode: "sandbox", provider: "aliyun")
        expect(result).to eq(cred)
      end

      it "raises CredentialsMissing when that provider has no active credential for the mode" do
        create(:sms_credential, provider: "aliyun", mode: "sandbox", status: "active")
        expect {
          described_class.call(mode: "sandbox", provider: "twilio")
        }.to raise_error(Sms::Errors::CredentialsMissing, I18n.t("admin_modules.sms.errors.credentials_missing"))
      end

      it "does not fall back to a different provider" do
        create(:sms_credential, provider: "twilio", mode: "sandbox", status: "active",
               config: { "from" => "+15551234567" })
        expect {
          described_class.call(mode: "sandbox", provider: "aliyun")
        }.to raise_error(Sms::Errors::CredentialsMissing)
      end
    end

    context "without a provider (nil)" do
      it "prefers the default adapter's credential when active" do
        default_cred = create(:sms_credential, provider: Sms::Adapters.default_key.to_s,
                              mode: "sandbox", status: "active")
        create(:sms_credential, provider: "twilio", mode: "sandbox", status: "active",
               config: { "from" => "+15551234567" })

        expect(described_class.call(mode: "sandbox")).to eq(default_cred)
      end

      it "falls back to any active credential for the mode when the default provider has none" do
        twilio_cred = create(:sms_credential, provider: "twilio", mode: "sandbox", status: "active",
                             config: { "from" => "+15551234567" })

        expect(described_class.call(mode: "sandbox")).to eq(twilio_cred)
      end
    end

    context "when no active credential exists" do
      it "raises Sms::Errors::CredentialsMissing" do
        expect {
          described_class.call(mode: "nonexistent_mode")
        }.to raise_error(Sms::Errors::CredentialsMissing, I18n.t("admin_modules.sms.errors.credentials_missing"))
      end

      %w[en zh-CN].each do |locale|
        it "localizes the error in #{locale} without exposing resolver diagnostics" do
          I18n.with_locale(locale) do
            expect { described_class.call(mode: "nonexistent_mode") }.to raise_error(Sms::Errors::CredentialsMissing) do |error|
              expect(error.message).to eq(I18n.t("admin_modules.sms.errors.credentials_missing"))
              expect(error.message).not_to include("sms_credentials", "mode=", "provider=")
            end
          end
        end
      end
    end

    it "ignores a disabled credential" do
      create(:sms_credential, provider: "aliyun", mode: "sandbox", status: "disabled")
      expect {
        described_class.call(mode: "sandbox", provider: "aliyun")
      }.to raise_error(Sms::Errors::CredentialsMissing)
    end
  end

  describe ".default_mode" do
    it "returns 'production' in production" do
      with_rails_env("production") do
        expect(described_class.default_mode).to eq("production")
      end
    end

    it "returns 'sandbox' in non-production" do
      with_rails_env("test") do
        expect(described_class.default_mode).to eq("sandbox")
      end
    end
  end

  describe ".call with default mode" do
    it "uses the mode from .default_mode when no mode given" do
      allow(described_class).to receive(:default_mode).and_return("sandbox")
      create(:sms_credential, mode: "sandbox", status: "active")
      expect { described_class.call }.not_to raise_error
    end
  end
end
