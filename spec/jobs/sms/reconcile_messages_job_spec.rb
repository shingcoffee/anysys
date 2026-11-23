# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::ReconcileMessagesJob do
  describe "#perform" do
    it "delegates to Sms::Cron::ReconcileMessages.call" do
      expect(Sms::Cron::ReconcileMessages).to receive(:call)
      described_class.new.perform
    end

    it "is enqueued on the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "preserves recent uncertainty and marks historical pending older than three days unknown without inventing failure" do
      travel_to(Time.utc(2026, 10, 13, 12)) do
        customer = create(:customer)
        recent = create(:sms_message, customer: customer, status: "pending", vendor_message_id: nil, created_at: 2.hours.ago)
        boundary = create(:sms_message, customer: customer, status: "pending", vendor_message_id: nil, created_at: 3.days.ago)
        stale = create(:sms_message, customer: customer, status: "pending", vendor_message_id: nil,
                       created_at: 3.days.ago - 1.second, raw_response: { "acceptance" => "unresolved" })
        expect(Sms::Gateway).not_to receive(:query)
        expect(Sms::DeliverMessageJob).not_to receive(:perform_later)

        described_class.perform_now

        expect(recent.reload).to have_attributes(status: "pending", failure_code: nil, failure_message: nil)
        expect(boundary.reload.status).to eq("pending")
        expect(stale.reload).to have_attributes(status: "unknown", failure_code: nil, failure_message: nil,
                                                raw_response: { "acceptance" => "unresolved" }, delivery_attempts: 0)
        travel 1.second
        described_class.perform_now
        expect(boundary.reload).to have_attributes(status: "unknown", failure_code: nil, failure_message: nil)
      end
    end

    it "leaves aged queued messages with stray vendor IDs to outbox recovery without querying or dispatching" do
      message = create(:sms_message, status: "queued", vendor_message_id: "STRAY_ID", created_at: 4.days.ago,
                       expires_at: 3.days.ago, delivery_enqueued_at: 4.days.ago)
      before_reconciliation = message.attributes
      expect(Sms::Gateway).not_to receive(:query)
      expect(Sms::DeliverMessageJob).not_to receive(:perform_later)

      described_class.perform_now

      expect(message.reload.attributes).to eq(before_reconciliation)
    end

    it "redrives a retained authenticated receipt before aging a message outside the REST query window" do
      customer = create(:customer)
      credential = create(:sms_credential, provider: "twilio", access_key_id: "AC_JOB", access_key_secret: "JOB_TOKEN",
                          config: { "messaging_service_sid" => "MG_JOB" }, status: "disabled")
      message = create(:sms_message, customer: customer, provider: "twilio", status: "pending", vendor_message_id: nil,
                       to: "+14155552671", created_at: 4.days.ago, dispatch_started_at: 4.days.ago,
                       metadata: { "credential_id" => credential.id, "credential_mode" => credential.mode })
      occurred_at = 3.days.ago.change(usec: 0)
      receipt = Sms::ReceiptInbox.record!(credential: credential, event: {
        type: :delivery, vendor_message_id: "SM_JOB", status: :delivered, phone: message.to,
        account_sid: "AC_JOB", occurred_at: occurred_at, provider_status: "delivered", segments: 2,
        raw: { "MessageSid" => "SM_JOB", "MessageStatus" => "delivered" }
      })
      expect(receipt).to have_attributes(customer_id: nil, processed_at: nil)
      message.update!(vendor_message_id: "SM_JOB")
      expect(Sms::Gateway).not_to receive(:query)
      expect(Sms::DeliverMessageJob).not_to receive(:perform_later)

      described_class.perform_now

      expect(message.reload).to have_attributes(status: "delivered", delivered_at: occurred_at, failure_code: nil, failure_message: nil)
      expect(message.metadata).to include("provider_status" => "delivered", "provider_segments" => 2)
      expect(receipt.reload.customer_id).to eq(customer.id)
      expect(receipt.processed_at).to be_present
    end
  end
end
