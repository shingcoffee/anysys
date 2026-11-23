# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Gateway do
  let_it_be(:customer) { create(:customer) }

  describe ".send" do
    it "delegates to Sms::Activities::Send with the same arguments" do
      expect(Sms::Activities::Send).to receive(:call).with(
        customer: customer, to: "+8613800138000", template_key: "verify_code",
        vars: { "code" => "1" }, idempotency_key: "k-1", mode: "production", provider: nil, expires_at: nil
      ).and_return(:msg)

      result = described_class.send(
        customer: customer, to: "+8613800138000", template_key: "verify_code",
        vars: { "code" => "1" }, idempotency_key: "k-1", mode: "production"
      )
      expect(result).to eq(:msg)
    end

    it "forwards an explicit provider through to the activity" do
      expect(Sms::Activities::Send).to receive(:call).with(
        customer: customer, to: "+8613800138000", template_key: "verify_code",
        vars: { "code" => "1" }, idempotency_key: nil, mode: nil, provider: "twilio", expires_at: nil
      ).and_return(:msg)

      described_class.send(customer: customer, to: "+8613800138000", template_key: "verify_code",
                           vars: { "code" => "1" }, provider: "twilio")
    end

    it "forwards caller-provided expiry to async admission" do
      expiry = 10.minutes.from_now
      expect(Sms::Activities::Send).to receive(:call).with(hash_including(expires_at: expiry)).and_return(:queued)
      expect(described_class.send(customer: customer, to: "+8613800138000", template_key: "verify_code", vars: {}, expires_at: expiry)).to eq(:queued)
    end
  end

  describe ".query" do
    let(:credential) { create(:sms_credential, provider: "aliyun") }
    let!(:message)   { create(:sms_message, customer: customer, provider: "aliyun", status: "sent",
                              vendor_message_id: "BIZ-1", sent_at: Time.zone.now) }

    it "resolves the credential using the message's provider" do
      expect(Sms::CredentialResolver).to receive(:call)
        .with(mode: Sms::CredentialResolver.default_mode, provider: "aliyun", credential_id: nil)
        .and_return(credential)
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:query)
        .and_return({ status: :unknown, raw: {} })

      described_class.query(message: message)
    end

    it "flips the message to :delivered when the adapter reports delivered" do
      allow(Sms::CredentialResolver).to receive(:call).and_return(credential)
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:query)
        .and_return({ status: :delivered, raw: { "Code" => "OK" } })

      described_class.query(message: message)
      expect(message.reload.status).to eq("delivered")
      expect(message.delivered_at).to be_present
    end

    it "flips the message to :failed when the adapter reports failed" do
      allow(Sms::CredentialResolver).to receive(:call).and_return(credential)
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:query)
        .and_return({ status: :failed, raw: {} })

      described_class.query(message: message)
      expect(message.reload.status).to eq("failed")
      expect(message.failure_message).to eq(Sms::Message::FAILURE_DELIVERY)
    end

    it "marks the message :unknown when the adapter reports unknown" do
      allow(Sms::CredentialResolver).to receive(:call).and_return(credential)
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:query)
        .and_return({ status: :unknown, raw: {} })

      described_class.query(message: message)
      expect(message.reload.status).to eq("unknown")
    end

    it "queries the recorded disabled credential and mode, preserving its identity" do
      message.update!(metadata: { credential_id: credential.id, credential_mode: credential.mode })
      credential.update!(status: "disabled")
      expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:query).and_return(status: :delivered, raw: {})
      described_class.query(message: message, mode: "production")
      expect(message.reload.status).to eq("delivered")
      expect(message.metadata).to include("credential_id" => credential.id, "credential_mode" => credential.mode)
    end

    it "does not project a response from an unexpected account" do
      allow(Sms::CredentialResolver).to receive(:call).and_return(credential)
      allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:query).and_return(status: :delivered, account_sid: "FOREIGN", raw: {})
      described_class.query(message: message)
      expect(message.reload.status).to eq("sent")
    end

    it "never queries or retries an unconfirmed attempt without provider identity" do
      message.update!(vendor_message_id: nil, status: "unknown")
      expect(Sms::CredentialResolver).not_to receive(:call)
      expect(described_class.query(message: message)).to eq(message)
      expect(message.reload.status).to eq("unknown")
    end
  end

  describe ".apply_query_result" do
    let!(:message) { create(:sms_message, customer: customer, status: "sent") }

    it "leaves the message untouched for an unrecognized status" do
      described_class.apply_query_result(message, { status: :something_else, raw: {} })
      expect(message.reload.status).to eq("sent")
    end

    it "rejects a query result for another or invalid recipient" do
      described_class.apply_query_result(message, status: :delivered, phone: "+8613800139999", raw: {})
      expect(message.reload.status).to eq("sent")
      described_class.apply_query_result(message, status: :delivered, phone: "call 13800138000", raw: {})
      expect(message.reload.status).to eq("sent")
    end

    it "preserves carrier failure details and synchronizes Twilio 21610 suppression" do
      message.update!(provider: "twilio", to: "+14155552671")
      described_class.apply_query_result(message, status: :failed, phone: "+14155552671", provider_status: "undelivered",
                                        failure_code: "21610", failure_message: "Recipient opted out", segments: 2, raw: {})
      expect(message.reload).to have_attributes(status: "failed", failure_code: "21610", failure_message: "Recipient opted out")
      expect(message.metadata).to include("provider_segments" => 2, "provider_status" => "undelivered")
      expect(Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: "+14155552671")).to be(true)
    end

    it "stores vendor delivery time and does not regress delivered on late failure" do
      occurred = Time.utc(2026, 10, 13, 10)
      described_class.apply_query_result(message, status: :delivered, occurred_at: occurred, segments: 3, provider_status: "delivered", raw: {})
      described_class.apply_query_result(message, status: :failed, failure_code: "late", segments: 1, provider_status: "failed", raw: {})
      expect(message.reload).to have_attributes(status: "delivered", delivered_at: occurred, failure_code: nil)
      expect(message.metadata).to include("provider_segments" => 3, "provider_status" => "delivered")
    end
  end
end
