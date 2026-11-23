# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Activities::SaveCredential do
  describe ".call — create" do
    it "persists a new SMTP credential with typed columns" do
      record = Emails::Credential.new
      params = {
        provider: "smtp", mode: "sandbox", status: "active",
        host: "smtp.example.com", port: "587", username: "user@example.com",
        password: "secret", authentication: "plain"
      }

      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(true)
      expect(result.model).to be_persisted
      expect(result.model.provider).to eq("smtp")
      expect(result.model.host).to eq("smtp.example.com")
    end

    it "persists a new SES credential with funneled config fields" do
      record = Emails::Credential.new
      params = {
        provider: "ses", mode: "sandbox", status: "active",
        password: "secret", access_key_id: "AKID", from_email: "noreply@example.com", region: "us-east-1",
        sns_topic_arn: "arn:aws:sns:us-east-1:1:ses"
      }

      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(true)
      expect(result.model.provider).to eq("ses")
      expect(result.model.config).to eq("access_key_id" => "AKID", "from_email" => "noreply@example.com",
                                        "region" => "us-east-1", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses")
    end

    it "returns success?=false with errors when validation fails" do
      record = Emails::Credential.new
      params = { provider: "smtp", mode: "", status: "active" }

      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(false)
      expect(result.errors).not_to be_empty
      expect(result.model).not_to be_persisted
    end

    it "adds a :taken error on mode when a RecordNotUnique race occurs" do
      create(:email_credential, provider: "smtp", mode: "sandbox")
      record = Emails::Credential.new
      allow(record).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)
      params = { provider: "smtp", mode: "sandbox", status: "active",
                 host: "h", port: "587", username: "u", password: "p", authentication: "plain" }

      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(false)
      expect(result.model.errors[:mode]).to be_present
    end
  end

  describe ".call — update" do
    let!(:record) do
      create(:email_credential, provider: "smtp", password: "original-secret",
             dkim_private_key: nil)
    end

    it "keeps the existing password when submitted blank" do
      params = { password: "" }
      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(true)
      expect(result.model.reload.password).to eq("original-secret")
    end

    it "rotates the password when a new value is submitted" do
      params = { password: "rotated-secret" }
      described_class.call(record: record, params: params)

      expect(record.reload.password).to eq("rotated-secret")
    end

    it "leaves dkim_private_key untouched when submitted blank" do
      record.update_columns(dkim_private_key: nil)
      params = { dkim_private_key: "" }
      described_class.call(record: record, params: params)

      expect(record.reload.dkim_private_key).to be_nil
    end
  end

  describe ".call — update for an SES credential" do
    let!(:record) do
      create(:email_credential, provider: "ses", host: nil, username: nil,
             password: "orig-secret", config: { "access_key_id" => "AKID", "from_email" => "orig@example.com",
                                                "region" => "us-east-1", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
    end

    it "clears a config field when submitted blank" do
      params = { region: "" }
      described_class.call(record: record, params: params)

      expect(record.reload.config).to eq("access_key_id" => "AKID", "from_email" => "orig@example.com",
                                         "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses")
    end

    it "updates a config field to a new value while leaving others untouched" do
      params = { from_email: "new@example.com" }
      described_class.call(record: record, params: params)

      expect(record.reload.config).to eq("access_key_id" => "AKID", "from_email" => "new@example.com",
                                         "region" => "us-east-1", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses")
    end

    it "leaves config untouched when no config keys are present in params" do
      params = { status: "disabled" }
      described_class.call(record: record, params: params)

      expect(record.reload.config).to eq("access_key_id" => "AKID", "from_email" => "orig@example.com",
                                         "region" => "us-east-1", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses")
      expect(record.status).to eq("disabled")
    end

    it "falls back to the record's existing config when the provider is unresolvable (ArgumentError)" do
      params = { provider: "unregistered_vendor", from_email: "ignored@example.com" }
      result = described_class.call(record: record, params: params)

      expect(result.success?).to be(false) # provider inclusion validation fails
      expect(record.config).to eq("access_key_id" => "AKID", "from_email" => "orig@example.com",
                                  "region" => "us-east-1", "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses")
    end
  end

  describe ".sanitize" do
    it "only assigns keys that are present in the incoming params" do
      record = build(:email_credential, provider: "smtp", status: "active")
      attrs  = described_class.sanitize({ status: "disabled" }, record)

      expect(attrs).to have_key(:status)
      expect(attrs).not_to have_key(:provider)
      expect(attrs).not_to have_key(:mode)
      expect(attrs).not_to have_key(:host)
    end
  end

  describe "delivery assignment invariant" do
    let!(:smtp) { create(:email_credential, mode: "sandbox", status: "active") }
    let!(:production) { create(:email_credential, :production, status: "active") }
    let(:ses) do
      build(:email_credential, provider: "ses", mode: "sandbox", status: "disabled",
            host: nil, username: nil, config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com",
                                               "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
    end

    it "routes an active credential-card save through the single-active assignment invariant" do
      result = described_class.call(record: ses, params: { status: "active" })

      expect(result.success?).to be(true)
      expect(Emails::Credential.active.where(mode: "sandbox")).to contain_exactly(ses)
      expect(smtp.reload.status).to eq("disabled")
      expect(production.reload.status).to eq("active")
    end

    it "rolls back sibling deactivation when the proposed active credential is invalid" do
      result = described_class.call(record: ses, params: { status: "active", from_email: "" })

      expect(result.success?).to be(false)
      expect(result.errors).to be_present
      expect(smtp.reload.status).to eq("active")
      expect(ses).not_to be_persisted
    end
  end
end
