# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::ReceiptInbox do
  let(:customer) { create(:customer) }
  let(:credential) do
    create(:sms_credential, provider: "twilio", access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN",
           config: { messaging_service_sid: "MG123" })
  end
  let(:message) do
    create(:sms_message, customer: customer, provider: "twilio", to: "+14155552671", status: "sent",
           vendor_message_id: "SM1", sent_at: 5.minutes.ago,
           metadata: { credential_id: credential.id, credential_mode: credential.mode, caller: "preserved" })
  end
  let(:event) do
    { type: :delivery, vendor_message_id: "SM1", status: :failed, phone: "+1 (415) 555-2671", provider_status: "undelivered",
      failure_code: "30003", failure_message: "Unreachable destination", segments: 2,
      occurred_at: Time.utc(2026, 10, 13, 10), account_sid: "AC_TEST", raw: { "ErrorCode" => "30003" } }
  end

  it "projects normalized receipt facts and preserves credential/caller metadata" do
    message
    receipt = described_class.record!(credential: credential, event: event)
    expect(message.reload).to have_attributes(status: "failed", failure_code: "30003", failure_message: "Unreachable destination")
    expect(message.metadata).to include("credential_id" => credential.id, "caller" => "preserved", "provider_segments" => 2,
                                       "provider_status" => "undelivered", "provider_occurred_at" => "2026-10-13T10:00:00Z")
    expect(receipt.reload).to have_attributes(customer_id: customer.id)
    expect(receipt.processed_at).to be_present
  end

  it "uses normalized phone instead of relying on raw To" do
    message
    described_class.record!(credential: credential, event: event.merge(status: :delivered, raw: { "To" => "irrelevant legacy blob" }))
    expect(message.reload.status).to eq("delivered")
    expect(message.delivered_at).to eq(Time.utc(2026, 10, 13, 10))
  end

  ["+14155552672", "call +14155552671", ["+14155552671"]].each do |phone|
    it "does not project or suppress a mismatched recipient #{phone.inspect}" do
      message
      receipt = described_class.record!(credential: credential, event: event.merge(phone: phone, failure_code: "21610"))
      expect(message.reload.status).to eq("sent")
      expect(receipt.reload.customer_id).to be_nil
      expect(receipt.processed_at).to be_nil
      expect(Sms::OptOut.count).to eq(0)
    end
  end

  it "does not attach another credential's message or disclose its tenant in the receipt" do
    message
    other = create(:sms_credential, provider: "twilio", mode: "production", access_key_id: "AC_OTHER",
                   access_key_secret: "TOKEN", config: { messaging_service_sid: "MG_OTHER" })
    receipt = described_class.record!(credential: other, event: event.except(:account_sid))
    expect(message.reload.status).to eq("sent")
    expect(receipt.reload.customer_id).to be_nil
    expect(receipt.processed_at).to be_nil
  end

  it "rejects an authenticated event whose account is not the bound credential" do
    message
    receipt = described_class.record!(credential: credential, event: event.merge(account_sid: "AC_OTHER"))
    expect(receipt.reload.processed_at).to be_nil
    expect(message.reload.status).to eq("sent")
  end

  it "retains and later projects an early receipt without guessing credential ownership" do
    receipt = described_class.record!(credential: credential, event: event)
    expect(receipt.processed_at).to be_nil
    message
    described_class.reconcile(provider: "twilio", vendor_message_id: "SM1")
    expect(receipt.reload.customer_id).to eq(customer.id)
    expect(message.reload.status).to eq("failed")
  end

  it "repairs unknown after the polling age limit, preserving delivered floor on late failure" do
    message.update!(status: "unknown", created_at: 5.days.ago)
    described_class.record!(credential: credential, event: event.merge(status: :delivered, provider_status: "delivered"))
    described_class.record!(credential: credential, event: event)
    expect(message.reload.status).to eq("delivered")
    expect(message.failure_code).to be_nil
    expect(message.metadata["provider_status"]).to eq("delivered")
  end

  it "synchronizes provider opt-out on a matched 21610 receipt" do
    message
    described_class.record!(credential: credential, event: event.merge(failure_code: "21610"))
    expect(Sms::OptOut.opted_out?(customer_id: customer.id, phone_e164: "+14155552671")).to be(true)
    expect(Sms::OptOut.find_by!(phone_e164: "+14155552671").reason).to eq("provider:21610")
  end

  it "deduplicates inbound SID identity and retains distinct STOP messages" do
    inbound = { type: :inbound, phone: "+14155552671", keyword: "STOP", account_sid: "AC_TEST", vendor_message_id: "SM_IN_1" }
    first = described_class.record!(credential: credential, event: inbound)
    same = described_class.record!(credential: credential, event: inbound.merge(raw: { "ignored" => "different audit text" }))
    other = described_class.record!(credential: credential, event: inbound.merge(vendor_message_id: "SM_IN_2"))
    expect(first.id).to eq(same.id)
    expect(other.id).not_to eq(first.id)
    expect(Sms::OptOut.where(phone_e164: "+14155552671").count).to eq(1)
  end

  it "never erases manual/global suppression for START or HELP classifications" do
    manual = Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: "+14155552671", reason: "manual")
    global = Sms::OptOut.record_global!(phone_e164: "+14155552671", reason: "inbound:STOP")
    adapter = Sms::Adapters::Twilio.new(credential: credential)
    %w[START HELP].each do |classification|
      request = double(request_parameters: { "From" => "+14155552671", "Body" => classification, "OptOutType" => classification })
      expect(adapter.parse_inbound(request)).to be_nil
    end
    expect(Sms::OptOut.where(id: [manual.id, global.id]).count).to eq(2)
  end

  it "does not fabricate provider segments when unavailable or zero" do
    message
    described_class.record!(credential: credential, event: event.merge(segments: 0))
    expect(message.reload.metadata).not_to have_key("provider_segments")
  end
end
