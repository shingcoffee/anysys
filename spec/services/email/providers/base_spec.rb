# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Providers::Base do
  subject(:provider) { concrete_class.new(credential: credential) }

  let(:credential) { double("credential") }
  let(:base)       { described_class.new(credential: credential) }

  # Build a minimal concrete subclass so we can test the shared HTTP helpers
  # (which are protected on Base).
  let(:concrete_class) do
    Class.new(described_class) do
      def test_safe_json(str) = safe_json(str)
      def test_http_post_json(url, body, headers: {}) = http_post_json(url, body, headers: headers)
      def test_http_post_form(url, params) = http_post_form(url, params)
    end
  end


  describe "abstract interface" do
    it "raises NotImplementedError on #deliver when not overridden" do
      expect { base.deliver(message: double("message")) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #verify_webhook! when not overridden" do
      expect { base.verify_webhook!(double("request")) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #parse_events when not overridden" do
      expect { base.parse_events(double("request")) }.to raise_error(NotImplementedError)
    end
  end

  describe "class-level defaults" do
    it ".key raises NotImplementedError on the abstract base" do
      expect { described_class.key }.to raise_error(NotImplementedError, /must declare \.key/)
    end

    it ".default_display_name raises NotImplementedError on the abstract base" do
      expect { described_class.default_display_name }.to raise_error(NotImplementedError, /must declare \.default_display_name/)
    end

    it ".config_fields defaults to an empty array" do
      expect(described_class.config_fields).to eq([])
    end

    it ".configured? defaults to false" do
      expect(described_class.configured?(double("credential"))).to be(false)
    end

    it ".delivery_mechanism defaults to :none" do
      expect(described_class.delivery_mechanism).to eq(:none)
    end

    it ".uses_webhook_secret? follows delivery_mechanism" do
      expect(described_class.uses_webhook_secret?).to be(false)
      expect(Email::Providers::Aliyun.uses_webhook_secret?).to be(true)
      expect(Email::Providers::Ses.uses_webhook_secret?).to be(false)
    end
  end

  it "accepts a full MIME-capable envelope by default for shared admission inspection" do
    message = build_stubbed(:email_message, :campaign, bcc: "private@example.com", reply_to: "reply@example.com",
                             body_html: '<img src="cid:blob-123">', metadata: { "attachment_blob_ids" => [123] })
    expect(base.supports_message?(message: message)).to be(true)
    expect(base.validate_message!(message: message)).to eq(message)
  end

  describe ".display_name" do
    it "falls back to default_display_name when no i18n key exists" do
      klass = Class.new(described_class) do
        def self.key = "stub_vendor"
        def self.default_display_name = "Stub Vendor"
      end
      expect(klass.display_name).to eq("Stub Vendor")
    end

    it "uses the localized name when present (ses)" do
      expect(Email::Providers::Ses.display_name).to eq(I18n.t("email.providers.ses.name"))
    end
  end

  describe ".field_label" do
    it "falls back to the field's :label when no i18n key exists" do
      klass = Class.new(described_class) do
        def self.key = "stub_vendor"
      end
      expect(klass.field_label(name: :widget, label: "Widget")).to eq("Widget")
    end

    it "uses the localized field label when present (ses from_email)" do
      field = Email::Providers::Ses.config_fields.find { |f| f[:name] == :from_email }
      expect(Email::Providers::Ses.field_label(field)).to eq(I18n.t("email.providers.ses.fields.from_email"))
    end
  end

  describe ".credential_label" do
    it "falls back through email.credentials.<name> then humanize" do
      klass = Class.new(described_class) do
        def self.key = "stub_vendor"
      end
      expect(klass.credential_label(:password)).to eq(I18n.t("email.credentials.password"))
      expect(klass.credential_label(:totally_unknown_field)).to eq("Totally unknown field")
    end

    it "uses the provider-specific localized label when present (ses password -> Secret Access Key)" do
      expect(Email::Providers::Ses.credential_label(:password)).to eq(I18n.t("email.providers.ses.credentials.password"))
    end
  end

  describe ".register! / .default!" do
    it "adds the class to the Email::Providers registry and can mark it default" do
      original_default = Email::Providers.default_key
      klass = Class.new(described_class) do
        def self.key = "stub_vendor_#{object_id}"
        def self.default_display_name = "Stub"
      end
      klass.register!
      expect(Email::Providers.for(klass.key)).to eq(klass)

      klass.default!
      expect(Email::Providers.default_key).to eq(klass.key.to_sym)
    ensure
      Email::Providers.instance_variable_get(:@registry)&.delete(klass.key.to_sym)
      Email::Providers.instance_variable_set(:@default_key, original_default)
    end
  end

  describe "#safe_json" do
    it "parses a valid JSON string" do
      expect(provider.test_safe_json('{"ok":true}')).to eq({ "ok" => true })
    end

    it "returns { 'raw' => str } for invalid JSON" do
      expect(provider.test_safe_json("not json {{")).to eq({ "raw" => "not json {{" })
    end

    it "handles nil input gracefully (nil.to_s = '')" do
      expect(provider.test_safe_json(nil)).to eq({ "raw" => "" })
    end
  end

  describe "#http_post_json — network error propagation" do
    it "wraps a transport failure in Email::Errors::TransportError" do
      stub_request(:post, "https://example.com/api").to_timeout
      expect {
        provider.test_http_post_json("https://example.com/api", { key: "value" }.to_json)
      }.to raise_error(Email::Errors::TransportError)
    end

    it "returns [response, parsed_json] on success" do
      stub_request(:post, "https://example.com/api").to_return(
        status: 200, body: { "ErrorCode" => 0 }.to_json
      )
      res, json = provider.test_http_post_json("https://example.com/api", { key: "value" }.to_json)
      expect(res.status).to eq(200)
      expect(json).to eq({ "ErrorCode" => 0 })
    end
  end

  describe "#http_post_form — network error propagation" do
    it "wraps a transport failure in Email::Errors::TransportError" do
      stub_request(:post, "https://example.com/form").to_timeout
      expect {
        provider.test_http_post_form("https://example.com/form", { key: "value" })
      }.to raise_error(Email::Errors::TransportError)
    end

    it "returns [response, parsed_json] on success" do
      stub_request(:post, "https://example.com/form").to_return(
        status: 200, body: { "EnvId" => "1" }.to_json
      )
      res, json = provider.test_http_post_form("https://example.com/form", { key: "value" })
      expect(res.status).to eq(200)
      expect(json).to eq({ "EnvId" => "1" })
    end
  end
end
