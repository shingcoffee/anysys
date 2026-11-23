# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS backend lifecycle" do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:sms_credential) }
  let!(:template) { create(:sms_template, variables: []) }

  before do
    enable_module!("sms", customer, name: "SMS")
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message).and_return(vendor_message_id: "vendor-id", raw: {})
  end

  def send_sms(**options)
    Sms::Gateway.send(**{ customer: customer, to: "+8613800138000", template_key: template.key, vars: {} }.merge(options))
  end

  it "treats blank idempotency keys as absent rather than replaying another phone's send" do
    first = send_sms(idempotency_key: "")
    second = send_sms(to: "+8613800138001", idempotency_key: "")
    expect(second.id).not_to eq(first.id)
    expect([first.idempotency_key, second.idempotency_key]).to eq([nil, nil])
  end

  it "replays before checking a subsequently retired template or exhausted cap" do
    first = send_sms(idempotency_key: "replay")
    template.update!(status: "retired")
    allow(Sms::Activities::Send).to receive(:daily_cap_for).and_return(0)

    expect(send_sms(idempotency_key: "replay").id).to eq(first.id)
  end

  it "enforces phone windows across templates" do
    send_sms
    other = create(:sms_template, variables: [])
    expect { send_sms(template_key: other.key) }.to raise_error(Sms::Errors::RateLimited)
    expect(Sms::Message.where(customer_id: customer.id).count).to eq(1)
  end

  it "does not share a tenant's phone counter with another customer" do
    send_sms
    other = create(:customer)
    enable_module!("sms", other, name: "SMS")
    expect { send_sms(customer: other) }.not_to raise_error
  end

  it "keeps delivery monotone when a poll holds a stale copy" do
    message = send_sms
    Sms::DeliverMessageJob.new.perform(message.id)
    stale = Sms::Message.find(message.id)
    message.mark_delivered!(at: Time.current, raw: {})
    stale.mark_unknown!(raw: {})
    stale.mark_failed!(code: "late", message: Sms::Message::FAILURE_DELIVERY, raw: {})
    expect(message.reload.status).to eq("delivered")
  end

  it "polls the recorded account and mode after unassignment" do
    message = send_sms
    Sms::DeliverMessageJob.new.perform(message.id)
    credential.update!(status: "disabled")
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:query).and_return(status: :delivered, raw: {})

    Sms::Gateway.query(message: message.reload)

    expect(message.reload.status).to eq("delivered")
    expect(message.metadata).to include("credential_id" => credential.id, "credential_mode" => credential.mode)
  end

  it "durably correlates an early delivery without accepting another account's ID" do
    receipt = Sms::ReceiptInbox.record!(credential: credential, event: { type: :delivery, vendor_message_id: "early", status: :delivered })
    other = create(:sms_credential, mode: "production")
    foreign = create(:sms_message, customer: create(:customer), status: "sent", vendor_message_id: "early",
                     metadata: { credential_id: other.id, credential_mode: other.mode })
    own = create(:sms_message, customer: customer, status: "sent", vendor_message_id: "early",
                 metadata: { credential_id: credential.id, credential_mode: credential.mode })

    Sms::ReceiptInbox.reconcile

    expect(own.reload.status).to eq("delivered")
    expect(foreign.reload.status).to eq("sent")
    expect(receipt.reload.customer_id).to eq(customer.id)
  end

  it "deduplicates authenticated inbound STOP and suppresses later sends" do
    event = { type: :inbound, phone: "+8613800138000", keyword: "STOP" }
    first = Sms::ReceiptInbox.record!(credential: credential, event: event)
    second = Sms::ReceiptInbox.record!(credential: credential, event: event)
    expect(first.id).to eq(second.id)
    expect(first.reload.processed_at).to be_present
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

    expect(send_sms.status).to eq("suppressed")
  end

  it "does not exceed the tenant daily cap when the phone differs" do
    allow(Sms::Activities::Send).to receive(:daily_cap_for).and_return(1)
    send_sms
    expect { send_sms(to: "+8613800138001") }.to raise_error(Sms::Errors::DailyCapExceeded)
    expect(Sms::Message.where(customer_id: customer.id).count).to eq(1)
  end
end
