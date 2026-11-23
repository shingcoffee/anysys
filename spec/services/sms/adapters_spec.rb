# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Adapters do
  describe ".ensure_loaded!" do
    it "loads every adapter file under app/services/sms/adapters/*.rb (except base)" do
      expect { described_class.ensure_loaded! }.not_to raise_error
      expect(described_class.keys).not_to be_empty
    end
  end

  describe ".keys" do
    it "returns the registered adapter keys as symbols" do
      expect(described_class.keys).to all(be_a(Symbol))
      expect(described_class.keys).to include(:aliyun, :twilio)
    end
  end

  describe ".all" do
    it "returns the registered adapter classes" do
      expect(described_class.all).to include(Sms::Adapters::Aliyun, Sms::Adapters::Twilio)
    end
  end

  describe ".for" do
    it "resolves a registered adapter by string key" do
      expect(described_class.for("aliyun")).to eq(Sms::Adapters::Aliyun)
    end

    it "resolves a registered adapter by symbol key" do
      expect(described_class.for(:twilio)).to eq(Sms::Adapters::Twilio)
    end

    it "raises ArgumentError for an unknown key" do
      expect { described_class.for("nexmo") }.to raise_error(ArgumentError, /unknown sms adapter/)
    end
  end

  describe ".default_key" do
    it "returns the adapter that declared default! (aliyun)" do
      expect(described_class.default_key).to eq(:aliyun)
    end
  end
end
