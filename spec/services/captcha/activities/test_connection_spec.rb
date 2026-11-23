# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Activities::TestConnection do
  let(:settings) { create(:captcha_provider_settings) } # aliyun, fully configured

  describe "not configured" do
    it "returns 'configuration_error' without calling the provider" do
      settings.update!(access_key_id: nil, access_key_secret: nil)
      settings.write_config(scene_id: nil)
      settings.save!
      expect(Captcha::Providers::Aliyun).not_to receive(:verify)
      result = described_class.call(settings: settings)
      expect(result.status).to eq("configuration_error")
      expect(result.ok?).to eq(false)
    end

    it "persists the not-configured diagnostic message" do
      settings.update!(access_key_id: nil)
      described_class.call(settings: settings)
      expect(settings.reload.last_health_check_message).to eq("not configured")
    end
  end

  describe "sends the sentinel probe token, bypassing the replay cache" do
    it "does not consume a replay digest for the probe token" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_return(outcome: :success, http_status: 200, raw: {})
      expect(Captcha::TokenReplay).not_to receive(:consume!)
      described_class.call(settings: settings)
    end

    it "passes the PROBE_TOKEN as the context's verify_param" do
      allow(Captcha::Providers::Aliyun).to receive(:verify) do |settings:, context:|
        expect(context.verify_param).to eq(described_class::PROBE_TOKEN)
        { outcome: :success, http_status: 200, raw: {} }
      end
      described_class.call(settings: settings)
    end

    it "tags the context action as :connection_test" do
      allow(Captcha::Providers::Aliyun).to receive(:verify) do |settings:, context:|
        expect(context.action).to eq(:connection_test)
        { outcome: :success, http_status: 200, raw: {} }
      end
      described_class.call(settings: settings)
    end
  end

  describe "outcome mapping" do
    it "maps :success to 'ok'" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_return(outcome: :success, http_status: 200, raw: {})
      result = described_class.call(settings: settings)
      expect(result.status).to eq("ok")
      expect(result.ok?).to eq(true)
    end

    it "maps :invalid to 'ok' (credentials reached the vendor; a sentinel token is expected to be rejected)" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_return(outcome: :invalid, http_status: 200, raw: {})
      result = described_class.call(settings: settings)
      expect(result.status).to eq("ok")
    end

    it "maps :configuration_error to 'configuration_error'" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_return(outcome: :configuration_error, http_status: 400, raw: { "Message" => "bad key" })
      result = described_class.call(settings: settings)
      expect(result.status).to eq("configuration_error")
    end

    it "maps :unreachable to 'unreachable'" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_return(outcome: :unreachable, http_status: nil, raw: nil)
      result = described_class.call(settings: settings)
      expect(result.status).to eq("unreachable")
    end

    it "maps a raised Captcha::Errors::TransportError to 'unreachable'" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_raise(Captcha::Errors::TransportError, "boom")
      result = described_class.call(settings: settings)
      expect(result.status).to eq("unreachable")
      expect(settings.reload.last_health_check_message).to eq("boom")
    end
  end

  describe "diagnostic_message" do
    it "prefers the vendor 'Message' field" do
      expect(described_class.diagnostic_message({ "Message" => "bad key" })).to eq("bad key")
    end

    it "falls back to a lowercase 'message' field" do
      expect(described_class.diagnostic_message({ "message" => "lowercase" })).to eq("lowercase")
    end

    it "falls back to joined error-codes when no message field is present" do
      expect(described_class.diagnostic_message({ "error-codes" => %w[a b] })).to eq("a, b")
    end

    it "returns nil for a non-Hash raw payload" do
      expect(described_class.diagnostic_message("raw string")).to be_nil
      expect(described_class.diagnostic_message(nil)).to be_nil
    end

    it "returns nil when there is nothing diagnostic to report" do
      expect(described_class.diagnostic_message({})).to be_nil
    end
  end

  describe "persistence" do
    it "writes last_health_check_at, _status, and _message on the settings row" do
      allow(Captcha::Providers::Aliyun).to receive(:verify).and_return(outcome: :success, http_status: 200, raw: {})
      described_class.call(settings: settings)
      expect(settings.reload).to have_attributes(
        last_health_check_status: "ok",
        last_health_check_at: be_present
      )
    end
  end
end
