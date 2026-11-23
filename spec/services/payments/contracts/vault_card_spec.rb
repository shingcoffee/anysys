# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Contracts::VaultCard do
  subject(:form) { described_class.new(OpenStruct.new(provider: provider, return_url: return_url)) }

  let(:provider)   { "stripe" }
  let(:return_url) { "https://example.com/return" }

  describe "valid input" do
    it "is valid for a stripe provider with return_url" do
      expect(form.validate(provider: "stripe", return_url: "https://example.com")).to be true
    end
  end

  describe "return_url validation" do
    it "is invalid without return_url" do
      expect(form.validate(provider: "stripe", return_url: nil)).to be false
      expect(form.errors[:return_url]).to be_present
    end

    it "is invalid with blank return_url" do
      expect(form.validate(provider: "stripe", return_url: "")).to be false
      expect(form.errors[:return_url]).to be_present
    end
  end

  describe "provider validation" do
    it "is invalid without provider" do
      expect(form.validate(provider: nil, return_url: "https://example.com")).to be false
      expect(form.errors[:provider]).to be_present
    end

    it "is invalid for an unregistered provider key" do
      expect(form.validate(provider: "paypal", return_url: "https://example.com")).to be false
      expect(form.errors[:provider]).to be_present
    end

    it "is invalid for a registered gateway that lacks :tokenized_cards capability" do
      # alipay is registered but does not have :tokenized_cards capability
      expect(form.validate(provider: "alipay", return_url: "https://example.com")).to be false
      expect(form.errors[:provider]).to be_present
    end
  end
end
