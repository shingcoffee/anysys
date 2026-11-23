# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Providers::Turnstile do
  let(:settings) do
    build_stubbed(:captcha_provider_settings, provider: "turnstile",
                  access_key_id: "SITE_KEY", access_key_secret: "SECRET_KEY", config: {}.to_json)
  end
  let(:adapter)  { described_class.new(settings: settings) }
  let(:endpoint) { described_class::SITEVERIFY_URL }

  def stub_verify(status:, body:, **opts)
    stub_json(:post, endpoint, status:, body:, **opts)
  end

  it_behaves_like "a captcha provider identity",
                  key: "turnstile", display_name: "Cloudflare Turnstile", score_based: false

  describe ".config_fields" do
    it "is empty — Site/Secret Key live in the shared credential columns" do
      expect(described_class.config_fields).to eq([])
    end
  end

  describe ".configured?" do
    it "is true when both access_key_id and access_key_secret are present" do
      expect(described_class.configured?(settings)).to eq(true)
    end

    it "is false when access_key_id is blank" do
      s = build_stubbed(:captcha_provider_settings, provider: "turnstile", access_key_id: nil, access_key_secret: "SECRET_KEY")
      expect(described_class.configured?(s)).to eq(false)
    end

    it "is false when access_key_secret is blank" do
      s = build_stubbed(:captcha_provider_settings, provider: "turnstile", access_key_id: "SITE_KEY", access_key_secret: nil)
      expect(described_class.configured?(s)).to eq(false)
    end
  end

  describe ".widget" do
    it "returns Stimulus + SDK metadata keyed off the site key" do
      meta = described_class.widget(settings)
      expect(meta[:stimulus_controller]).to eq("captcha-turnstile")
      expect(meta[:sdk_url]).to eq(described_class::SDK_URL)
      expect(meta[:data]["captcha-turnstile-site-key-value"]).to eq("SITE_KEY")
    end
  end

  describe ".credential_label" do
    it "renders 'Site Key' for access_key_id" do
      expect(described_class.credential_label(:access_key_id)).to eq("Site Key")
    end

    it "renders 'Secret Key' for access_key_secret" do
      expect(described_class.credential_label(:access_key_secret)).to eq("Secret Key")
    end
  end

  describe "#verify" do
    let(:context) { Captcha::VerificationContext.new(verify_param: "tok") }

    context "remoteip present" do
      let(:context) { Captcha::VerificationContext.new(verify_param: "tok", remoteip: "1.2.3.4") }

      it "includes remoteip in the siteverify POST" do
        stub_verify(status: 200, body: { "success" => true })
        adapter.verify(context: context)
        expect(WebMock).to have_requested(:post, endpoint).with { |req|
          body = URI.decode_www_form(req.body).to_h
          body["secret"] == "SECRET_KEY" && body["response"] == "tok" && body["remoteip"] == "1.2.3.4"
        }
      end
    end

    context "remoteip absent" do
      let(:context) { Captcha::VerificationContext.new(verify_param: "tok") }

      it "omits remoteip from the siteverify POST" do
        stub_verify(status: 200, body: { "success" => true })
        adapter.verify(context: context)
        expect(WebMock).to have_requested(:post, endpoint).with { |req|
          body = URI.decode_www_form(req.body).to_h
          body["secret"] == "SECRET_KEY" && body["response"] == "tok" && !body.key?("remoteip")
        }
      end
    end


    it "maps success == true to :success and echoes the hostname" do
      stub_verify(status: 200, body: { "success" => true, "hostname" => "example.com" })
      result = adapter.verify(context: context)
      expect(result).to eq(outcome: :success, http_status: 200, raw: { "success" => true, "hostname" => "example.com" },
                            score: nil, hostname: "example.com")
    end

    it "maps success == false with a non-config error-code to :invalid" do
      stub_verify(status: 200, body: { "success" => false, "error-codes" => ["timeout-or-duplicate"] })
      expect(adapter.verify(context: context)[:outcome]).to eq(:invalid)
    end

    it "maps success == false with no error-codes to :invalid" do
      stub_verify(status: 200, body: { "success" => false })
      expect(adapter.verify(context: context)[:outcome]).to eq(:invalid)
    end

    described_class::CONFIG_ERROR_CODES.each do |code|
      it "maps success == false with error-code '#{code}' to :configuration_error" do
        stub_verify(status: 200, body: { "success" => false, "error-codes" => [code] })
        expect(adapter.verify(context: context)[:outcome]).to eq(:configuration_error)
      end
    end

    it "trusts the body over a 4xx status when the body carries a definitive success" do
      # Body-trumps-4xx: an attacker-influenced token that somehow rides a 4xx
      # response must still classify as :invalid (hard block), never a
      # fail-open :configuration_error.
      stub_verify(status: 400, body: { "success" => false, "error-codes" => ["invalid-input-response"] })
      expect(adapter.verify(context: context)[:outcome]).to eq(:invalid)
    end

    it "trusts a config-error body even when carried on a 4xx status" do
      stub_verify(status: 400, body: { "success" => false, "error-codes" => ["invalid-input-secret"] })
      expect(adapter.verify(context: context)[:outcome]).to eq(:configuration_error)
    end

    it "maps HTTP 5xx to :unreachable regardless of body" do
      stub_verify(status: 503, body: { "success" => true })
      expect(adapter.verify(context: context)[:outcome]).to eq(:unreachable)
    end

    it "maps a 4xx with no usable body (no 'success' key) to :configuration_error" do
      stub_verify(status: 400, body: "not-json")
      expect(adapter.verify(context: context)[:outcome]).to eq(:configuration_error)
    end

    it "maps a 2xx with no usable body (no 'success' key) to :unreachable" do
      stub_verify(status: 200, body: "not-json")
      expect(adapter.verify(context: context)[:outcome]).to eq(:unreachable)
    end

    it "maps a timeout to :unreachable with a nil http_status" do
      stub_request(:post, endpoint).to_timeout
      out = adapter.verify(context: context)
      expect(out).to eq(outcome: :unreachable, http_status: nil, raw: nil, score: nil)
    end

    context "server-bound hostname and action" do
      # Official Siteverify response fields:
      # https://developers.cloudflare.com/turnstile/get-started/server-side-validation/
      let(:context) { Captcha::VerificationContext.new(verify_param: "tok", hostname: "example.com", action: :sign_in) }
      let(:valid_body) { { "success" => true, "hostname" => "example.com", "action" => "sign_in", "challenge_ts" => "2022-02-28T15:14:30.096Z", "error-codes" => [] } }

      it "accepts the expected hostname and action" do
        stub_verify(status: 200, body: valid_body)
        expect(adapter.verify(context: context)[:outcome]).to eq(:success)
      end

      [{ "hostname" => "evil.example" }, { "hostname" => nil },
       { "action" => "sign_up" }, { "action" => nil }].each do |change|
        it "hard-rejects a successful token with context mismatch #{change.inspect}" do
          stub_verify(status: 200, body: valid_body.merge(change))
          expect(adapter.verify(context: context)[:outcome]).to eq(:invalid)
        end
      end

      it "matches the interstitial SDK's omitted action but rejects tokens issued for another action" do
        challenge = Captcha::VerificationContext.new(verify_param: "tok", hostname: "example.com", action: :access_challenge)
        stub_verify(status: 200, body: valid_body.except("action"))
        expect(adapter.verify(context: challenge)[:outcome]).to eq(:success)
        stub_verify(status: 200, body: valid_body)
        expect(adapter.verify(context: challenge)[:outcome]).to eq(:invalid)
      end
    end

    [nil, [], true, 123].each do |body|
      it "handles non-object vendor body #{body.inspect} as unreachable rather than raising" do
        stub_verify(status: 200, body: body)
        expect(adapter.verify(context: context)[:outcome]).to eq(:unreachable)
      end
    end
  end
end
