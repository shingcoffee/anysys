# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Errors do
  describe "hierarchy" do
    it "Sms::Errors::Error is a StandardError" do
      expect(Sms::Errors::Error.ancestors).to include(StandardError)
    end

    %w[CredentialsMissing TemplateNotFound TemplateVarsInvalid DailyCapExceeded Suppressed TransportError SignatureInvalid].each do |klass_name|
      it "Sms::Errors::#{klass_name} inherits from Sms::Errors::Error" do
        klass = described_class.const_get(klass_name)
        expect(klass.ancestors).to include(Sms::Errors::Error)
      end
    end
  end

  describe Sms::Errors::RateLimited do
    it "stores the window attribute" do
      err = described_class.new(window: "daily")
      expect(err.window).to eq("daily")
    end

    it "uses a default message when msg is nil" do
      err = described_class.new(window: "daily")
      expect(err.message).to include("daily")
    end

    it "uses a custom message when msg is provided" do
      err = described_class.new(window: "hourly", msg: "Too many requests")
      expect(err.message).to eq("Too many requests")
    end

    it "inherits from Sms::Errors::Error" do
      expect(described_class.ancestors).to include(Sms::Errors::Error)
    end
  end

  describe Sms::Errors::ApiError do
    it "stores code and payload" do
      err = described_class.new("API failure", code: "ERR_001", payload: { detail: "bad" })
      expect(err.message).to eq("API failure")
      expect(err.code).to    eq("ERR_001")
      expect(err.payload).to eq({ detail: "bad" })
    end

    it "defaults code and payload to nil" do
      err = described_class.new("Error")
      expect(err.code).to    be_nil
      expect(err.payload).to be_nil
    end

    it "inherits from Sms::Errors::Error" do
      expect(described_class.ancestors).to include(Sms::Errors::Error)
    end
  end

  describe Sms::Errors::TransportError do
    it "retains a known vendor ID and compact partial-response payload" do
      payload = { "sid" => "SM_KNOWN", "status" => "malformed" }
      error = described_class.new("unconfirmed response", vendor_message_id: "SM_KNOWN", payload: payload)
      expect(error.message).to eq("unconfirmed response")
      expect(error.vendor_message_id).to eq("SM_KNOWN")
      expect(error.payload).to eq(payload)
    end

    it "supports ordinary message-only raises without response facts" do
      expect { raise described_class, "timeout" }.to raise_error(described_class) { |error|
        expect(error.message).to eq("timeout")
        expect(error.vendor_message_id).to be_nil
        expect(error.payload).to be_nil
      }
    end

    it "allows a partial response without an explicit message" do
      error = described_class.new(vendor_message_id: "SM_KNOWN", payload: {})
      expect(error.vendor_message_id).to eq("SM_KNOWN")
      expect(error.payload).to eq({})
    end
  end
end
