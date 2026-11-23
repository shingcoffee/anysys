# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::CredentialResolver do
  describe ".call" do
    context "when a single active credential exists for the mode (no provider named)" do
      let!(:credential) { create(:email_credential, mode: "production", status: "active") }

      it "returns it" do
        result = described_class.call(mode: "production")
        expect(result).to eq(credential)
      end
    end

    context "when an explicit provider is named" do
      let!(:smtp_credential) { create(:email_credential, provider: "smtp", mode: "sandbox", status: "active") }
      let!(:ses_credential) do
        create(:email_credential, provider: "ses", mode: "sandbox", status: "active",
               host: nil, username: nil, password: "secret",
               config: { "access_key_id" => "AKID", "from_email" => "a@b.com", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
      end

      it "returns the credential for that provider" do
        expect(described_class.call(mode: "sandbox", provider: "ses")).to eq(ses_credential)
      end

      it "raises CredentialsMissing when that provider has no active credential for the mode" do
        smtp_credential.update!(status: "disabled")
        expect { described_class.call(mode: "sandbox", provider: "smtp") }
          .to raise_error(Email::Errors::CredentialsMissing, /provider=smtp/)
      end
    end

    context "when no provider is named and multiple providers have active credentials" do
      let!(:ses_credential) do
        create(:email_credential, provider: "ses", mode: "sandbox", status: "active",
               host: nil, username: nil, password: "secret",
               config: { "access_key_id" => "AKID", "from_email" => "a@b.com", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
      end
      let!(:smtp_credential) { create(:email_credential, provider: "smtp", mode: "sandbox", status: "active") }

      it "prefers the default provider (smtp)" do
        expect(described_class.call(mode: "sandbox")).to eq(smtp_credential)
      end

      it "falls back to any active credential for the mode when the default provider isn't configured" do
        smtp_credential.update!(status: "disabled")
        expect(described_class.call(mode: "sandbox")).to eq(ses_credential)
      end
    end

    context "when credential is disabled" do
      let!(:credential) { create(:email_credential, mode: "production", status: "disabled") }

      it "raises CredentialsMissing" do
        expect { described_class.call(mode: "production") }
          .to raise_error(Email::Errors::CredentialsMissing, /no active email credential/)
      end
    end

    context "when no credential exists" do
      it "raises CredentialsMissing" do
        expect { described_class.call(mode: "sandbox") }
          .to raise_error(Email::Errors::CredentialsMissing)
      end
    end

    it "defaults mode to default_mode when omitted (used by the webhook path)" do
      cred = create(:email_credential, mode: "sandbox", status: "active")
      allow(described_class).to receive(:default_mode).and_return("sandbox")
      expect(described_class.call).to eq(cred)
    end
  end

  describe ".default_mode" do
    it "returns production in production environment" do
      with_rails_env("production") do
        expect(described_class.default_mode).to eq("production")
      end
    end

    it "returns sandbox in non-production environments" do
      with_rails_env("development") do
        expect(described_class.default_mode).to eq("sandbox")
      end
    end
  end

  describe ".for_recorded" do
    let!(:original) { create(:email_credential, :disabled, provider: "smtp", mode: "sandbox") }

    it "resolves the disabled credential by its recorded identity for receipt verification" do
      expect(described_class.for_recorded(credential_id: original.id, provider: "smtp", mode: "sandbox"))
        .to eq(original)
      expect { described_class.call(provider: "smtp", mode: "sandbox") }
        .to raise_error(Email::Errors::CredentialsMissing)
    end

    it "does not fall back to another credential for a provider or mode mismatch" do
      expect { described_class.for_recorded(credential_id: original.id, provider: "ses") }
        .to raise_error(Email::Errors::CredentialsMissing)
      expect { described_class.for_recorded(credential_id: original.id, provider: "smtp", mode: "production") }
        .to raise_error(Email::Errors::CredentialsMissing)
    end

    it "requires an explicit recorded identity" do
      expect { described_class.for_recorded(credential_id: nil, provider: "smtp") }
        .to raise_error(Email::Errors::CredentialsMissing)
    end
  end
end
