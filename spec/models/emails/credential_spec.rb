# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Credential, type: :model do
  let(:pem) { OpenSSL::PKey::RSA.new(1024).to_pem }

  # A DKIM-enabled credential with valid domain/selector/key; override any field to
  # exercise a missing/invalid input.
  def dkim_credential(**overrides)
    build(:email_credential, dkim_enabled: true, dkim_domain: "example.com",
          dkim_selector: "mail", dkim_private_key: pem, **overrides)
  end

  def api_credential(**overrides)
    build(:email_credential, provider: "ses", host: nil, username: nil,
          password: "secret", mode: "sandbox",
          config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com",
                    "sns_topic_arn" => "arn:aws:sns:us-east-1:1:receipts" }, **overrides)
  end

  describe "validations" do
    it "is valid with required attributes (defaults to smtp provider)" do
      credential = build(:email_credential)
      expect(credential).to be_valid
      expect(credential.provider).to eq("smtp")
    end

    it "requires provider to be a registered Email::Providers key" do
      credential = build(:email_credential, provider: "unregistered_vendor")
      expect(credential).not_to be_valid
      expect(credential.errors[:provider]).to be_present
    end

    it "is valid for an API provider without SMTP typed fields" do
      expect(api_credential).to be_valid
    end

    it "is valid for ses and aliyun providers without SMTP typed fields" do
      ses = build(:email_credential, provider: "ses", host: nil, username: nil, password: "secret",
                  config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com",
                            "sns_topic_arn" => "arn:aws:sns:us-east-1:1:receipts" })
      aliyun = build(:email_credential, provider: "aliyun", host: nil, username: nil, password: "AKS",
                     webhook_secret: "whsec",
                     config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com" })
      expect(ses).to be_valid
      expect(aliyun).to be_valid
    end

    context "smtp-only conditional validations" do
      it "requires host" do
        expect(build(:email_credential, host: nil)).not_to be_valid
      end

      it "requires port" do
        expect(build(:email_credential, port: nil)).not_to be_valid
      end

      it "rejects negative port numbers" do
        credential = build(:email_credential, port: -1)
        expect(credential).not_to be_valid
        expect(credential.errors[:port]).to be_present
      end

      it "rejects port numbers above 65535" do
        credential = build(:email_credential, port: 70000)
        expect(credential).not_to be_valid
        expect(credential.errors[:port]).to be_present
      end

      it "requires username" do
        expect(build(:email_credential, username: nil)).not_to be_valid
      end

      it "does not require host/username for a non-smtp provider" do
        credential = api_credential(host: nil, username: nil)
        expect(credential).to be_valid
      end
    end

    it "requires password" do
      expect(build(:email_credential, password: nil)).not_to be_valid
    end

    it "requires mode" do
      expect(build(:email_credential, mode: nil)).not_to be_valid
    end

    it "validates mode is in allowed values" do
      expect(build(:email_credential, mode: "sandbox")).to be_valid
      expect(build(:email_credential, mode: "production")).to be_valid
      expect(build(:email_credential, mode: "invalid")).not_to be_valid
    end

    it "requires mode to be unique scoped to provider" do
      create(:email_credential, provider: "smtp", mode: "sandbox")
      expect(build(:email_credential, provider: "smtp", mode: "sandbox")).not_to be_valid
    end

    it "allows the same mode for two different providers" do
      create(:email_credential, provider: "smtp", mode: "sandbox")
      expect(api_credential(mode: "sandbox")).to be_valid
    end

    it "validates status is in allowed values" do
      expect(build(:email_credential, status: "active")).to be_valid
      expect(build(:email_credential, status: "disabled")).to be_valid
      expect(build(:email_credential, status: "invalid")).not_to be_valid
    end

    it "validates authentication is in allowed values (smtp only)" do
      expect(build(:email_credential, authentication: "plain")).to be_valid
      expect(build(:email_credential, authentication: "login")).to be_valid
      expect(build(:email_credential, authentication: "cram_md5")).to be_valid
      expect(build(:email_credential, authentication: "invalid")).not_to be_valid
    end

    describe "#configured_when_active" do
      it "is invalid when active but not configured (missing ses from_email)" do
        credential = api_credential(config: {})
        expect(credential).not_to be_valid
        expect(credential.errors[:base]).to include(I18n.t("email.credentials.errors.incomplete"))
      end

      it "is valid when disabled and not fully configured" do
        credential = api_credential(config: {}, status: "disabled")
        expect(credential).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active_prod) { create(:email_credential, mode: "production", status: "active") }
    let!(:disabled_sandbox) { create(:email_credential, mode: "sandbox", status: "disabled") }

    it ".active returns only active credentials" do
      expect(described_class.active).to contain_exactly(active_prod)
    end
  end

  describe "#enabled?" do
    it "returns true when status is active" do
      expect(build(:email_credential, status: "active").enabled?).to be true
    end

    it "returns false when status is disabled" do
      expect(build(:email_credential, status: "disabled").enabled?).to be false
    end
  end

  describe "#smtp?" do
    it "is true for the smtp provider" do
      expect(build(:email_credential, provider: "smtp").smtp?).to be true
    end

    it "is false for a non-smtp provider" do
      expect(api_credential.smtp?).to be false
    end
  end

  describe "#provider_class" do
    it "resolves the registered provider class" do
      expect(build(:email_credential, provider: "smtp").provider_class).to eq(Email::Providers::Smtp)
      expect(api_credential.provider_class).to eq(Email::Providers::Ses)
    end

    it "returns nil for an unresolvable provider (ArgumentError rescued)" do
      credential = build(:email_credential)
      credential.provider = "unregistered_vendor"
      expect(credential.provider_class).to be_nil
    end
  end

  describe "#configured?" do
    it "delegates to the provider class's .configured?" do
      expect(build(:email_credential, host: "smtp.test", username: "u", password: "p").configured?).to be true
    end

    it "is false when provider_class is nil" do
      credential = build(:email_credential)
      credential.provider = "unregistered_vendor"
      expect(credential.configured?).to be false
    end
  end

  describe "#config_value / #write_config" do
    it "reads a stored config value with a default fallback" do
      credential = build(:email_credential, config: { "from_email" => "a@b.com" })
      expect(credential.config_value(:from_email)).to eq("a@b.com")
      expect(credential.config_value(:missing, "fallback")).to eq("fallback")
    end

    it "merges new keys into the existing config, stringifying keys" do
      credential = build(:email_credential, config: { "a" => "1" })
      credential.write_config(b: "2")
      expect(credential.config).to eq("a" => "1", "b" => "2")
    end
  end

  describe "#from_address" do
    it "uses the SMTP username when present" do
      credential = build(:email_credential, username: "smtp-user@example.com")
      expect(credential.from_address).to eq("smtp-user@example.com")
    end

    it "uses config from_email for API providers" do
      credential = api_credential
      expect(credential.from_address).to eq("noreply@example.com")
    end

    %w[ses aliyun].each do |provider|
      it "ignores a leftover SMTP username for the #{provider} API provider" do
        credential = api_credential(provider: provider, username: "historical-smtp@example.com")
        expect(credential.from_address).to eq("noreply@example.com")
      end
    end

    it "does not use API config as a fallback for an incomplete SMTP username" do
      credential = build(:email_credential, username: nil, config: { "from_email" => "api@example.com" })
      expect(credential.from_address).to be_nil
    end
  end

  describe "encryption" do
    it "encrypts the password field at rest" do
      credential = create(:email_credential, password: "secret123")
      raw = ActiveRecord::Base.connection.select_one(
        "SELECT password FROM email_credentials WHERE id = #{credential.id}"
      )["password"]
      expect(raw).not_to include("secret123")
      expect(credential.reload.password).to eq("secret123")
    end
  end

  describe "#dkim_configured?" do
    it "returns true when smtp, dkim_enabled, and all fields are present" do
      expect(dkim_credential.dkim_configured?).to be true
    end

    it "returns false when dkim_enabled is false" do
      expect(dkim_credential(dkim_enabled: false).dkim_configured?).to be false
    end

    it "returns false when dkim_domain is blank" do
      expect(dkim_credential(dkim_domain: nil).dkim_configured?).to be false
    end

    it "returns false when dkim_selector is blank" do
      expect(dkim_credential(dkim_selector: nil).dkim_configured?).to be false
    end

    it "returns false when dkim_private_key is blank" do
      expect(dkim_credential(dkim_private_key: nil).dkim_configured?).to be false
    end

    it "returns false for a non-smtp provider even with dkim fields populated" do
      credential = api_credential
      credential.dkim_enabled = true
      credential.dkim_domain = "example.com"
      credential.dkim_selector = "mail"
      credential.dkim_private_key = pem
      expect(credential.dkim_configured?).to be false
    end
  end

  describe "#dkim_dns_txt_record" do
    it "returns the selector._domainkey TXT record derived from the key when configured" do
      record = dkim_credential.dkim_dns_txt_record
      expect(record).to include("mail._domainkey.example.com")
      expect(record).to include("v=DKIM1; k=rsa; p=")
    end

    it "returns nil when DKIM is not configured" do
      expect(build(:email_credential, dkim_enabled: false).dkim_dns_txt_record).to be_nil
    end

    it "returns nil when the stored key is not a valid RSA key (PKeyError rescued)" do
      expect(dkim_credential(dkim_private_key: "not-a-key").dkim_dns_txt_record).to be_nil
    end
  end

  describe "DKIM validations" do
    it "requires dkim_domain, dkim_selector, dkim_private_key when dkim_enabled" do
      credential = build(:email_credential,
        dkim_enabled: true,
        dkim_domain: nil,
        dkim_selector: nil,
        dkim_private_key: nil)
      expect(credential).not_to be_valid
      expect(credential.errors[:dkim_domain]).to be_present
      expect(credential.errors[:dkim_selector]).to be_present
      expect(credential.errors[:dkim_private_key]).to be_present
    end

    it "does not require DKIM fields when dkim_enabled is false" do
      credential = build(:email_credential,
        dkim_enabled: false,
        dkim_domain: nil,
        dkim_selector: nil,
        dkim_private_key: nil)
      expect(credential).to be_valid
    end
  end

  describe "DKIM private key encryption" do
    it "stores dkim_private_key encrypted (raw DB value differs from plaintext)" do
      pem = OpenSSL::PKey::RSA.new(1024).to_pem
      credential = create(:email_credential,
        mode: "production",
        dkim_enabled: true,
        dkim_domain: "example.com",
        dkim_selector: "mail",
        dkim_private_key: pem)
      raw = described_class.connection.select_value(
        "SELECT dkim_private_key FROM email_credentials WHERE id=#{credential.id}"
      )
      expect(raw).not_to eq(pem)
      expect(credential.reload.dkim_private_key).to eq(pem)
    end
  end
end
