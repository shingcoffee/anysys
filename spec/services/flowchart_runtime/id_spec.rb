# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Id do
  describe ".generate" do
    it "returns a uuid" do
      result = described_class.generate(type: "uuid")
      expect(result).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "returns a ulid" do
      result = described_class.generate(type: "ulid")
      expect(result).to match(/\A[0-9A-Z]{26}\z/)
    end

    it "returns a nanoid with default size" do
      result = described_class.generate(type: "nanoid")
      expect(result.length).to eq(21)
    end

    it "returns a nanoid with custom size and alphabet" do
      result = described_class.generate(type: "nanoid", size: 8, alphabet: "ABC123")
      expect(result.length).to eq(8)
      expect(result).to match(/\A[ABC123]{8}\z/)
    end

    it "returns a hash with requested length" do
      result = described_class.generate(type: "hash", length: 16)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[0-9a-f]{16}\z/)
    end

    it "returns hash IDs with exact odd lengths" do
      [1, 15, 21].each do |length|
        expect(described_class.generate(type: "hash", length:).length).to eq(length)
      end
    end

    it "returns a custom_pattern id" do
      result = described_class.generate(type: "custom_pattern", pattern: "ORD-%Y%m%d-")
      expect(result).to start_with("ORD-")
      expect(result.length).to be > 10
    end

    it "applies prefix, separator, and uppercase" do
      result = described_class.generate(type: "uuid", prefix: "user", separator: "_", uppercase: true)
      expect(result).to start_with("user_")
      expect(result.split("_", 2).last).to eq(result.split("_", 2).last.upcase)
    end

    it "raises Error for unsupported type" do
      expect { described_class.generate(type: "snowflake") }
        .to raise_error(FlowchartRuntime::Id::Error, /unsupported id type/)
    end

    it "raises Error for empty nanoid alphabet" do
      expect { described_class.generate(type: "nanoid", alphabet: "") }
        .to raise_error(FlowchartRuntime::Id::Error, /alphabet must be a non-empty string/)
    end

    it "returns hex of the requested byte length" do
      result = described_class.generate(type: "hex", length: 16)
      expect(result).to match(/\A[0-9a-f]+\z/)
      expect(result.length).to eq(16)
    end

    it "returns urlsafe base64" do
      result = described_class.generate(type: "urlsafe_base64", length: 8)
      expect(result).to be_a(String)
      expect(result).not_to include("+", "/")
    end

    it "returns secure_random hex" do
      result = described_class.generate(type: "secure_random", length: 4)
      expect(result).to match(/\A[0-9a-f]{8}\z/)
    end

    it "returns base58 from the Token facade" do
      result = described_class.generate(type: "base58", length: 8)
      expect(result).to match(/\A[1-9A-HJ-NP-Za-km-z]+\z/)
    end
  end
end
