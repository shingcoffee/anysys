# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Activities::SaveCredential do
  describe ".call — create" do
    it "persists a new credential with funneled provider-specific config fields" do
      record = Sms::Credential.new
      params = {
        provider: "aliyun", mode: "sandbox", status: "active",
        access_key_id: "AKID", access_key_secret: "AKS",
        sign_name: "TestCo", region: "cn-hangzhou"
      }

      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(true)
      expect(result.model).to be_persisted
      expect(result.model.provider).to eq("aliyun")
      expect(result.model.config).to eq("sign_name" => "TestCo", "region" => "cn-hangzhou")
    end

    it "returns success?=false with errors when validation fails" do
      record = Sms::Credential.new
      params = { provider: "aliyun", mode: "", status: "active" }

      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(false)
      expect(result.errors).not_to be_empty
      expect(result.model).not_to be_persisted
    end
  end

  describe ".call — update" do
    let!(:record) do
      create(:sms_credential, provider: "aliyun", access_key_secret: "original-secret",
             config: { "sign_name" => "OrigCo", "region" => "cn-hangzhou" })
    end

    it "keeps the existing access_key_secret when submitted blank" do
      params = { access_key_secret: "" }
      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(true)
      expect(result.model.reload.access_key_secret).to eq("original-secret")
    end

    it "rotates the access_key_secret when a new value is submitted" do
      params = { access_key_secret: "rotated-secret" }
      described_class.call(record: record, params: params)

      expect(record.reload.access_key_secret).to eq("rotated-secret")
    end

    it "clears a config field when submitted blank" do
      params = { region: "" }
      described_class.call(record: record, params: params)

      expect(record.reload.config).to eq("sign_name" => "OrigCo")
    end

    it "updates a config field to a new value while leaving others untouched" do
      params = { sign_name: "NewCo" }
      described_class.call(record: record, params: params)

      expect(record.reload.config).to eq("sign_name" => "NewCo", "region" => "cn-hangzhou")
    end

    it "leaves config untouched when no config keys are present in params" do
      params = { status: "disabled" }
      described_class.call(record: record, params: params)

      expect(record.reload.config).to eq("sign_name" => "OrigCo", "region" => "cn-hangzhou")
      expect(record.status).to eq("disabled")
    end

    it "falls back to the record's existing config when the provider is unresolvable (ArgumentError)" do
      params = { provider: "unknown_vendor", sign_name: "Ignored" }
      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(false) # provider inclusion validation fails
      expect(record.config).to eq("sign_name" => "OrigCo", "region" => "cn-hangzhou")
    end
  end

  describe ".sanitize" do
    it "only assigns keys that are present in the incoming params" do
      record = build(:sms_credential, provider: "aliyun", status: "active")
      attrs  = described_class.sanitize({ status: "disabled" }, record)

      expect(attrs).to have_key(:status)
      expect(attrs).not_to have_key(:provider)
      expect(attrs).not_to have_key(:mode)
      expect(attrs).not_to have_key(:access_key_id)
    end
  end

  describe "single-active delivery assignment" do
    let!(:previous) { create(:sms_credential, provider: "aliyun", mode: "sandbox", status: "active") }
    let!(:production) { create(:sms_credential, provider: "aliyun", mode: "production", status: "active") }
    let(:selected) do
      build(:sms_credential, provider: "twilio", mode: "sandbox", status: "disabled",
            access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN", config: { "messaging_service_sid" => "MG1" })
    end

    it "selects an active credential-card save and disables only same-mode siblings" do
      result = described_class.call(record: selected, params: { status: "active" })

      expect(result.success?).to be(true)
      expect(Sms::Credential.active.where(mode: "sandbox")).to contain_exactly(selected)
      expect(Sms::CredentialResolver.call(mode: "sandbox")).to eq(selected)
      expect(previous.reload.status).to eq("disabled")
      expect(production.reload.status).to eq("active")
    end

    it "rolls back sibling deactivation if the active credential fails validation" do
      result = described_class.call(record: selected, params: { status: "active", messaging_service_sid: "" })

      expect(result.success?).to be(false)
      expect(result.errors).to be_present
      expect(selected).not_to be_persisted
      expect(previous.reload.status).to eq("active")
    end

    it "keeps a disabled credential edit from changing the selected vendor" do
      selected.save!
      result = described_class.call(record: selected, params: { access_key_secret: "rotated" })

      expect(result.success?).to be(true)
      expect(selected.reload.status).to eq("disabled")
      expect(previous.reload.status).to eq("active")
    end

    it "rolls back sibling deactivation after a uniqueness race" do
      allow(selected).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)
      result = described_class.call(record: selected, params: { status: "active" })

      expect(result.success?).to be(false)
      expect(result.model.errors[:mode]).to be_present
      expect(previous.reload.status).to eq("active")
    end
  end
end
