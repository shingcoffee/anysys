# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Providers::GoogleRecaptchaV3 do
  let(:settings) do
    Captcha::ProviderSettings.new(
      provider: "google_recaptcha_v3",
      access_key_id: "site-key",
      access_key_secret: "secret-key",
      score_threshold: 0.5
    )
  end
  let(:context) { Captcha::VerificationContext.new(verify_param: "token-123", remoteip: "1.2.3.4") }
  let(:provider) { described_class.new(settings: settings) }

  it_behaves_like "a captcha provider identity",
                  key: "google_recaptcha_v3", display_name: "Google reCAPTCHA v3",
                  score_based: true

  describe ".invisible?" do
    it "returns true" do
      expect(described_class.invisible?).to be(true)
    end
  end

  describe ".configured?" do
    it "returns true when keys are present" do
      expect(described_class.configured?(settings)).to be(true)
    end

    it "returns false when keys are missing" do
      settings.access_key_secret = nil
      expect(described_class.configured?(settings)).to be(false)
    end
  end

  describe ".widget" do
    it "returns the Stimulus controller name and data values including the SDK URL" do
      widget = described_class.widget(settings)

      expect(widget[:stimulus_controller]).to eq("captcha-google-recaptcha-v3")
      expect(widget[:data]["captcha-google-recaptcha-v3-site-key-value"]).to eq("site-key")
      expect(widget[:data]["captcha-google-recaptcha-v3-sdk-url-value"]).to eq(
        "https://www.google.com/recaptcha/api.js?render=site-key"
      )
    end
  end

  describe "#verify" do
    let(:url) { "https://www.google.com/recaptcha/api/siteverify" }

    it "returns success when score is above threshold" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: true, score: 0.9, hostname: "example.com" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:success)
      expect(result[:score]).to eq(0.9)
      expect(result[:hostname]).to eq("example.com")
    end

    it "returns invalid when score is below threshold" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: true, score: 0.3 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:invalid)
      expect(result[:score]).to eq(0.3)
    end

    it "returns invalid when success is false" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: false, "error-codes" => ["invalid-input-response"] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:invalid)
      expect(result[:score]).to be_nil
    end

    it "returns configuration_error for config related error codes" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: false, "error-codes" => ["invalid-input-secret"] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:configuration_error)
    end

    it "returns unreachable for 5xx errors" do
      stub_request(:post, url).to_return(status: 500)

      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:unreachable)
    end

    context "server-bound hostname and action" do
      # https://developers.google.com/recaptcha/docs/v3#site_verify_response
      let(:context) { Captcha::VerificationContext.new(verify_param: "tok", hostname: "example.com", action: :access_challenge) }
      let(:valid_body) { { success: true, score: 0.9, action: "submit", hostname: "example.com", challenge_ts: "2024-07-10T12:00:00Z" } }

      it "matches the actual interstitial SDK submit action" do
        stub_json(:post, url, status: 200, body: valid_body)
        expect(provider.verify(context: context)[:outcome]).to eq(:success)
      end

      [{ hostname: "evil.example" }, { hostname: nil }, { action: "sign_in" }, { action: nil }].each do |change|
        it "hard-rejects a successful token with context mismatch #{change.inspect}" do
          stub_json(:post, url, status: 200, body: valid_body.merge(change))
          expect(provider.verify(context: context)[:outcome]).to eq(:invalid)
        end
      end

      [nil, "0.9", {}, [], -0.1, 1.1].each do |score|
        it "rejects an invalid score shape #{score.inspect}" do
          stub_json(:post, url, status: 200, body: valid_body.merge(score: score))
          expect(provider.verify(context: context)[:outcome]).to eq(:invalid)
        end
      end
    end

    [nil, [], true, 123].each do |body|
      it "handles non-object vendor body #{body.inspect} as unreachable" do
        stub_json(:post, url, status: 200, body: body)
        expect(provider.verify(context: context)[:outcome]).to eq(:unreachable)
      end
    end
  end
end
