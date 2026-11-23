# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::CustomerSignupToken do
  let(:email) { "founder@acme.test" }

  describe ".normalize" do
    it "strips and downcases" do
      expect(described_class.normalize("  Foo@Example.COM ")).to eq("foo@example.com")
    end
  end

  describe ".generate / .verify" do
    it "round-trips a normalized email" do
      token = described_class.generate("  Founder@Acme.TEST ")

      expect(described_class.verify(token)).to eq("founder@acme.test")
    end

    it "does not put the email in plaintext in the token" do
      token = described_class.generate(email)

      expect(token).not_to include(email)
      expect(token.downcase).not_to include(email)
    end

    it "returns nil for a blank token" do
      expect(described_class.verify(nil)).to be_nil
      expect(described_class.verify("")).to be_nil
      expect(described_class.verify("   ")).to be_nil
    end

    it "returns nil after the TTL" do
      token = described_class.generate(email)

      travel(described_class::TTL + 1.second) do
        expect(described_class.verify(token)).to be_nil
      end
    end

    it "returns nil for tampered ciphertext" do
      token = described_class.generate(email)

      expect(described_class.verify("#{token}x")).to be_nil
    end

    it "returns nil for a token minted with a different purpose" do
      secret = Rails.application.key_generator.generate_key(described_class::PURPOSE, 32)
      other = ActiveSupport::MessageEncryptor.new(secret, serializer: JSON)
      token = other.encrypt_and_sign(
        { "email" => email },
        purpose: "member_mfa_reset",
        expires_in: described_class::TTL
      )

      expect(described_class.verify(token)).to be_nil
    end

    it "returns nil for a token minted with a different key" do
      secret = Rails.application.key_generator.generate_key("other_purpose", 32)
      other = ActiveSupport::MessageEncryptor.new(secret, serializer: JSON)
      token = other.encrypt_and_sign(
        { "email" => email },
        purpose: described_class::PURPOSE,
        expires_in: described_class::TTL
      )

      expect(described_class.verify(token)).to be_nil
    end
  end
end
