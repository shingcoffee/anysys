# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Errors do
  describe "hierarchy" do
    it "Payments::Errors::Error is a StandardError" do
      expect(Payments::Errors::Error.ancestors).to include(StandardError)
    end

    %w[CredentialsMissing TransportError SignatureInvalid TenantNotFound].each do |klass_name|
      it "Payments::Errors::#{klass_name} inherits from Payments::Errors::Error" do
        klass = described_class.const_get(klass_name)
        expect(klass.ancestors).to include(Payments::Errors::Error)
      end
    end
  end

  describe Payments::Errors::ApiError do
    it "stores message, code, and payload" do
      err = described_class.new("Upstream error", code: "4002", payload: { msg: "bad" })
      expect(err.message).to eq("Upstream error")
      expect(err.code).to    eq("4002")
      expect(err.payload).to eq({ msg: "bad" })
    end

    it "defaults code to nil and payload to empty hash" do
      err = described_class.new("Error")
      expect(err.code).to    be_nil
      expect(err.payload).to eq({})
    end

    it "inherits from Payments::Errors::Error" do
      expect(described_class.ancestors).to include(Payments::Errors::Error)
    end

    it "can be rescued as StandardError" do
      expect {
        raise described_class.new("fail")
      }.to raise_error(StandardError)
    end

    it "defaults an unclassified API failure to uncertain even when its code looks like a rejection" do
      error = described_class.new("Unknown vendor outcome", code: 402)
      expect(error).to be_uncertain
      expect(error).not_to be_definitive
      expect(error.classification).to eq(:uncertain)
    end

    it "accepts explicit provider evidence of non-execution" do
      error = described_class.new("Confirmed decline", code: 402, definitive: true)
      expect(error).to be_definitive
      expect(error).not_to be_uncertain
      expect(error.classification).to eq(:definitive_rejection)
    end

    [409, "429", 500, "503"].each do |code|
      it "never retires the operation on uncertain HTTP status #{code}" do
        error = described_class.new("Retry/reconcile", code: code, definitive: true)
        expect(error).to be_uncertain
        expect(error).not_to be_definitive
      end
    end

    it "does not confuse an Alipay business code with an HTTP server status" do
      expect(described_class.new("Invalid parameter", code: "40004", definitive: true)).to be_definitive
    end
  end

  it "always classifies transport/timeouts as uncertain" do
    error = Payments::Errors::TransportError.new("timeout")
    expect(error).to be_uncertain
    expect(error).not_to be_definitive
  end
end
