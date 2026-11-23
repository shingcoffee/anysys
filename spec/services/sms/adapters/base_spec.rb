# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Adapters::Base do
  subject(:adapter) { concrete_class.new(credential: credential) }

  let(:credential) { double("credential") }
  let(:base)       { described_class.new(credential: credential) }

  # Build a minimal concrete subclass so we can test the shared HTTP helpers
  # (which are protected on Base).
  let(:concrete_class) do
    Class.new(described_class) do
      def send_message(**); "sent"; end
      def query(**);        "queried"; end

      def test_safe_json(str) = safe_json(str)
      def test_http_post_form(url, params) = http_post_form(url, params)
      def test_malformed_response(**attributes) = malformed_response!(**attributes)
    end
  end


  describe "abstract interface" do
    it "raises NotImplementedError on send_message when not overridden" do
      expect {
        base.send_message(to: "+1", template: double("template"), template_params: {})
      }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on query when not overridden" do
      expect { base.query(message: double("message")) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on verify_webhook! when not overridden" do
      expect { base.verify_webhook!(double("request")) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on parse_delivery_receipt when not overridden" do
      expect { base.parse_delivery_receipt(double("request")) }.to raise_error(NotImplementedError)
    end

    it "#parse_inbound defaults to nil (not every vendor supports inbound STOP)" do
      expect(base.parse_inbound(double("request"))).to be_nil
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

    it ".delivery_mechanism defaults to :poll" do
      expect(described_class.delivery_mechanism).to eq(:poll)
    end

    it "allows minimal adapters without query fallback while real vendors opt in" do
      expect(described_class.query_supported?).to be(false)
      expect(Sms::Adapters::Aliyun.query_supported?).to be(true)
      expect(Sms::Adapters::Twilio.query_supported?).to be(true)
    end

    it ".rate_limit_windows defaults to DEFAULT_RATE_LIMIT_WINDOWS" do
      expect(described_class.rate_limit_windows).to eq(described_class::DEFAULT_RATE_LIMIT_WINDOWS)
    end
  end

  describe ".display_name" do
    it "falls back to default_display_name when no i18n key exists" do
      klass = Class.new(described_class) do
        def self.key = "stub_vendor"
        def self.default_display_name = "Stub Vendor"
      end
      expect(klass.display_name).to eq("Stub Vendor")
    end

    it "uses the localized name when present (aliyun)" do
      expect(Sms::Adapters::Aliyun.display_name).to eq(I18n.t("sms.adapters.aliyun.name"))
    end
  end

  describe ".field_label" do
    it "falls back to the field's :label when no i18n key exists" do
      klass = Class.new(described_class) do
        def self.key = "stub_vendor"
      end
      expect(klass.field_label(name: :widget, label: "Widget")).to eq("Widget")
    end
  end

  describe ".credential_label" do
    it "falls back through sms.credentials.<name> then humanize" do
      klass = Class.new(described_class) do
        def self.key = "stub_vendor"
      end
      expect(klass.credential_label(:access_key_id)).to eq(I18n.t("sms.credentials.access_key_id"))
      expect(klass.credential_label(:totally_unknown_field)).to eq("Totally unknown field")
    end
  end

  describe ".register! / .default!" do
    it "adds the class to the Sms::Adapters registry and can mark it default" do
      original_default = Sms::Adapters.default_key
      klass = Class.new(described_class) do
        def self.key = "stub_vendor_#{object_id}"
        def self.default_display_name = "Stub"
      end
      klass.register!
      expect(Sms::Adapters.for(klass.key)).to eq(klass)

      klass.default!
      expect(Sms::Adapters.default_key).to eq(klass.key.to_sym)
    ensure
      Sms::Adapters.instance_variable_get(:@registry)&.delete(klass.key.to_sym)
      Sms::Adapters.instance_variable_set(:@default_key, original_default)
    end
  end

  describe "#safe_json" do
    it "parses a valid JSON string" do
      result = adapter.test_safe_json('{"ok":true}')
      expect(result).to eq({ "ok" => true })
    end

    it "returns { 'raw' => str } for invalid JSON" do
      result = adapter.test_safe_json("not json {{")
      expect(result).to eq({ "raw" => "not json {{" })
    end

    it "handles nil input gracefully (nil.to_s = '')" do
      result = adapter.test_safe_json(nil)
      # JSON.parse("") raises ParserError → fallback
      expect(result).to eq({ "raw" => "" })
    end
  end

  describe "#http_post_form — network error propagation" do
    it "wraps a transport failure in Sms::Errors::TransportError" do
      stub_request(:post, "https://example.com/api").to_timeout
      expect {
        adapter.test_http_post_form("https://example.com/api", { key: "value" })
      }.to raise_error(Sms::Errors::TransportError)
    end

    it "returns [response, parsed_json] on success" do
      stub_request(:post, "https://example.com/api").to_return(
        status: 200, body: { "Code" => "OK" }.to_json
      )
      res, json = adapter.test_http_post_form("https://example.com/api", { key: "value" })
      expect(res.status).to eq(200)
      expect(json).to eq({ "Code" => "OK" })
    end
  end

  describe "#malformed_response! correlation" do
    it "retains a bounded syntactic provider ID and selected audit hash without proving acceptance" do
      expect { adapter.test_malformed_response(vendor_message_id: "12345^67890", raw: { "Code" => "OK" }) }
        .to raise_error(Sms::Errors::TransportError) { |error|
          expect(error.vendor_message_id).to eq("12345^67890")
          expect(error.payload).to eq("Code" => "OK")
        }
    end

    [nil, [], "", " ", "id\n", "id/other", "a" * 257].each do |id|
      it "never retains unsafe ID #{id.inspect}" do
        expect { adapter.test_malformed_response(vendor_message_id: id, raw: []) }
          .to raise_error(Sms::Errors::TransportError) { |error|
            expect(error.vendor_message_id).to be_nil
            expect(error.payload).to be_nil
          }
      end
    end
  end
end
