# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Providers::Base do
  # Minimal concrete subclass — lets us test shared helpers without needing
  # a real vendor integration.
  subject(:provider) { concrete_class.new(settings: settings) }

  let(:settings) { double("settings") }
  let(:context)  { Captcha::VerificationContext.new(verify_param: "tok") }

  let(:concrete_class) do
    Class.new(described_class) do
      def self.key          = "test_provider"
      def self.default_display_name = "Test Provider"

      def verify(context:)
        { outcome: :success, http_status: 200, raw: {} }
      end

      # Expose protected helpers for testing
      def test_safe_json(str)             = safe_json(str)
      def test_http_post_form(url, params) = http_post_form(url, params)
      def test_with_transport_rescue(&block) = with_transport_rescue(&block)
    end
  end

  describe "class-level interface" do
    it "raises NotImplementedError for .key on base class" do
      expect { described_class.key }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for .default_display_name on base class" do
      expect { described_class.default_display_name }.to raise_error(NotImplementedError)
    end

    it ".display_name falls back to .default_display_name when no translation exists" do
      expect(concrete_class.display_name).to eq("Test Provider")
    end

    it ".display_name uses the I18n translation when present" do
      allow(I18n).to receive(:t).with("captcha.providers.test_provider.name", default: "Test Provider")
                                 .and_return("Localized Name")
      expect(concrete_class.display_name).to eq("Localized Name")
    end

    it ".config_fields returns empty array by default" do
      expect(described_class.config_fields).to eq([])
    end

    it ".field_label falls back to the field's English label" do
      field = { name: :scene_id, label: "Scene ID" }
      expect(concrete_class.field_label(field)).to eq("Scene ID")
    end

    it ".field_label uses the I18n translation when present" do
      field = { name: :scene_id, label: "Scene ID" }
      allow(I18n).to receive(:t).with("captcha.providers.test_provider.fields.scene_id", default: "Scene ID")
                                 .and_return("Localized Scene")
      expect(concrete_class.field_label(field)).to eq("Localized Scene")
    end

    it ".credential_label falls back to the generic platform_settings label" do
      expect(concrete_class.credential_label(:access_key_id)).to eq(I18n.t("captcha.platform_settings.access_key_id"))
    end

    it ".credential_label uses a per-provider override when present" do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with("captcha.providers.test_provider.credentials.access_key_id", default: anything)
                                 .and_return("Site Key")
      expect(concrete_class.credential_label(:access_key_id)).to eq("Site Key")
    end

    it ".score_based? returns false by default" do
      expect(described_class.score_based?).to eq(false)
    end

    it ".configured? returns false by default" do
      expect(described_class.configured?(nil)).to be(false)
    end

    it ".widget returns nil by default" do
      expect(described_class.widget(nil)).to be_nil
    end

    it ".invisible? returns false by default" do
      expect(described_class.invisible?).to be(false)
    end

    it ".verify delegates to instance#verify" do
      allow_any_instance_of(concrete_class).to receive(:verify).with(context: context).and_return({ outcome: :success })
      result = concrete_class.verify(settings: settings, context: context)
      expect(result[:outcome]).to eq(:success)
    end

    it ".register! adds the class to the Captcha::Providers registry" do
      expect(Captcha::Providers).to receive(:register).with(concrete_class)
      concrete_class.register!
    end

    it ".default! marks the class as the registry default" do
      expect(Captcha::Providers).to receive(:mark_default).with(concrete_class)
      concrete_class.default!
    end
  end

  describe "#verify on base class raises NotImplementedError" do
    it do
      base = described_class.new(settings: settings)
      expect { base.verify(context: context) }.to raise_error(NotImplementedError)
    end
  end

  describe "#safe_json" do
    it "parses valid JSON" do
      expect(provider.test_safe_json('{"success":true}')).to eq({ "success" => true })
    end

    it "returns { 'raw' => str } on invalid JSON" do
      expect(provider.test_safe_json("not-json")).to eq({ "raw" => "not-json" })
    end

    it "handles nil gracefully" do
      expect(provider.test_safe_json(nil)).to eq({ "raw" => "" })
    end

    %w[null true 123 []].each do |body|
      it "maps non-object JSON #{body} into a diagnostic object" do
        expect(provider.test_safe_json(body)).to eq("raw" => body)
      end
    end
  end

  describe "#http_post_form — TransportError propagation" do
    it "wraps connection errors in Captcha::Errors::TransportError" do
      stub_request(:post, "https://captcha.example.com/verify").to_timeout
      expect {
        provider.test_http_post_form("https://captcha.example.com/verify", { token: "abc" })
      }.to raise_error(Captcha::Errors::TransportError)
    end

    it "returns the [response, parsed_json] pair on success" do
      stub_request(:post, "https://captcha.example.com/verify")
        .to_return(status: 200, body: { "ok" => true }.to_json)
      res, json = provider.test_http_post_form("https://captcha.example.com/verify", { token: "abc" })
      expect(res.code.to_i).to eq(200)
      expect(json).to eq({ "ok" => true })
    end
  end

  describe "#with_transport_rescue" do
    it "returns the block's value when it does not raise" do
      result = provider.test_with_transport_rescue { { outcome: :success, http_status: 200, raw: {}, score: nil } }
      expect(result).to eq(outcome: :success, http_status: 200, raw: {}, score: nil)
    end

    it "maps a Captcha::Errors::TransportError raised inside the block to the shared :unreachable shape" do
      result = provider.test_with_transport_rescue { raise Captcha::Errors::TransportError, "boom" }
      expect(result).to eq(outcome: :unreachable, http_status: nil, raw: nil, score: nil)
    end

    it "maps malformed outbound configuration to a controlled configuration outcome" do
      result = provider.test_with_transport_rescue { raise OutboundHttp::InvalidRequestError, "invalid URI" }
      expect(result).to eq(outcome: :configuration_error, http_status: nil, raw: nil, score: nil)
    end
  end

  describe "timeout constants" do
    it "OPEN_TIMEOUT is 2" do
      expect(described_class::OPEN_TIMEOUT).to eq(2)
    end

    it "READ_TIMEOUT is 3" do
      expect(described_class::READ_TIMEOUT).to eq(3)
    end
  end
end
