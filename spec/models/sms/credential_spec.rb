# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Credential do
  it "is valid with all required attributes" do
    expect(build(:sms_credential)).to be_valid
  end

  it "rejects an unknown provider" do
    c = build(:sms_credential, provider: "nexmo")
    expect(c).not_to be_valid
    expect(c.errors[:provider]).to include("is not included in the list")
  end

  it "accepts every registered adapter key as provider" do
    Sms::Adapters.keys.each do |key|
      c = build(:sms_credential, provider: key.to_s)
      c.valid?
      expect(c.errors[:provider]).to be_empty
    end
  end

  it "rejects an unknown mode" do
    c = build(:sms_credential, mode: "staging")
    expect(c).not_to be_valid
    expect(c.errors[:mode]).to include("is not included in the list")
  end

  it "enforces uniqueness on mode scoped to provider" do
    create(:sms_credential, provider: "aliyun", mode: "sandbox")
    dup = build(:sms_credential, provider: "aliyun", mode: "sandbox")
    expect(dup).not_to be_valid
  end

  it "allows the same mode across different providers" do
    create(:sms_credential, provider: "aliyun", mode: "sandbox")
    other = build(:sms_credential, provider: "twilio", mode: "sandbox",
                                   config: { "messaging_service_sid" => "MG123" })
    expect(other).to be_valid
  end

  it "encrypts access_key_secret at rest" do
    cred = create(:sms_credential, access_key_secret: "top-secret")
    raw  = ActiveRecord::Base.connection.select_one(
      "SELECT access_key_secret FROM sms_credentials WHERE id = #{cred.id}"
    )["access_key_secret"]
    expect(raw).not_to include("top-secret")
    expect(cred.reload.access_key_secret).to eq("top-secret")
  end

  it "scopes .active to status='active'" do
    active   = create(:sms_credential, mode: "sandbox",    status: "active")
    disabled = create(:sms_credential, mode: "production", status: "disabled")
    expect(described_class.active).to include(active)
    expect(described_class.active).not_to include(disabled)
  end

  describe "#configured_when_active" do
    it "is invalid when activated without a complete adapter config" do
      c = build(:sms_credential, provider: "aliyun", status: "active",
                                 config: { "sign_name" => "" })
      expect(c).not_to be_valid
      expect(c.errors[:base]).to include(I18n.t("sms.credentials.errors.incomplete"))
    end

    it "allows saving an incomplete credential when disabled (draft)" do
      c = build(:sms_credential, provider: "aliyun", status: "disabled",
                                 config: { "sign_name" => "" })
      expect(c).to be_valid
    end

    it "is valid when active and the adapter reports configured" do
      c = build(:sms_credential, provider: "aliyun", status: "active",
                                 config: { "sign_name" => "MyApp" })
      expect(c).to be_valid
    end
  end

  describe "#enabled?" do
    it "is true when status is active" do
      expect(build(:sms_credential, status: "active")).to be_enabled
    end

    it "is false when status is disabled" do
      expect(build(:sms_credential, status: "disabled")).not_to be_enabled
    end
  end

  describe "#adapter_class" do
    it "resolves the registered adapter for the provider" do
      cred = build(:sms_credential, provider: "aliyun")
      expect(cred.adapter_class).to eq(Sms::Adapters::Aliyun)
    end

    it "returns nil for an unregistered provider (bypassing validation)" do
      cred = build(:sms_credential)
      cred.provider = "nope"
      expect(cred.adapter_class).to be_nil
    end
  end

  describe "#configured?" do
    it "delegates to the adapter's configured? check" do
      cred = build(:sms_credential, provider: "aliyun", config: { "sign_name" => "MyApp" })
      expect(cred.configured?).to be(true)
    end

    it "is false when the adapter cannot resolve" do
      cred = build(:sms_credential)
      cred.provider = "nope"
      expect(cred.configured?).to be(false)
    end
  end

  describe "#config_value / #write_config" do
    it "reads a value from the config blob with a default fallback" do
      cred = build(:sms_credential, config: { "sign_name" => "MyApp" })
      expect(cred.config_value(:sign_name)).to eq("MyApp")
      expect(cred.config_value(:missing, "fallback")).to eq("fallback")
    end

    it "merges new keys into the existing config, stringifying keys" do
      cred = build(:sms_credential, config: { "sign_name" => "MyApp" })
      cred.write_config(region: "us-east-1")
      expect(cred.config).to eq("sign_name" => "MyApp", "region" => "us-east-1")
    end
  end
end
