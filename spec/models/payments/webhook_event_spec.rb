# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::WebhookEvent do
  it "overwrites PSP-supplied internal identity and keeps it out of the handler payload" do
    event = described_class.new(payload: described_class.payload_with_verification(
      { "id" => "evt_1", "_anysys_verification" => { "merchant_account_id" => 999 },
        "_anysys_processing" => { "token" => "vendor-forged" } }, signing_account_id: 123
    ))

    expect(event.signing_account_id).to eq(123)
    expect(event.verified_payload).to eq("id" => "evt_1")
  end
  it "enforces one row per (provider, psp_event_id)" do
    described_class.create!(provider: "stripe", psp_event_id: "evt_1", status: "processed")
    dup = described_class.new(provider: "stripe", psp_event_id: "evt_1", status: "processed")
    expect(dup).not_to be_valid
    expect(dup.errors[:psp_event_id]).to be_present
  end

  it "allows the same event id across different providers" do
    described_class.create!(provider: "stripe", psp_event_id: "id_x", status: "processed")
    other = described_class.new(provider: "paypal", psp_event_id: "id_x", status: "processed")
    expect(other).to be_valid
  end

  it "mark_processed! stamps status and processed_at" do
    e = described_class.create!(provider: "wechat_pay", psp_event_id: "w1", status: "received")
    e.mark_processed!
    expect(e.reload.status).to eq("processed")
    expect(e.processed_at).to be_present
  end

  it "mark_processed! backfills customer_id when one is passed" do
    e = described_class.create!(provider: "wechat_pay", psp_event_id: "w2", status: "received")
    e.mark_processed!(customer_id: 42)
    expect(e.reload.customer_id).to eq(42)
  end

  it "mark_processed! keeps the existing customer_id when none is passed" do
    e = described_class.create!(provider: "wechat_pay", psp_event_id: "w3", status: "received", customer_id: 7)
    e.mark_processed!
    expect(e.reload.customer_id).to eq(7)
  end

  it "persists the verified payload as JSON" do
    e = described_class.create!(provider: "stripe", psp_event_id: "evt_pay",
                                status: "processed", payload: { "type" => "payment_intent.succeeded" })
    expect(e.reload.payload["type"]).to eq("payment_intent.succeeded")
  end

  describe "processing lease" do
    let(:event) do
      create(:payment_webhook_event, status: "received", signing_merchant_id: "merchant",
             payload: described_class.payload_with_verification({ "id" => "lease-event" }, signing_account_id: 123))
    end

    it "recovers an expired claim without letting its old worker complete or release the new claim" do
      old_token = event.claim_processing!(signing_account_id: 123)
      travel described_class::PROCESSING_LEASE + 1.second do
        new_token = event.claim_processing!(signing_account_id: 123)

        expect(new_token).to be_present
        expect(new_token).not_to eq(old_token)
        expect(event.finish_processing!(old_token)).to be(false)
        event.release_processing!(old_token)
        expect(event.reload.processing?).to be(true)
        expect(event.finish_processing!(new_token)).to be(true)
      end
      expect(event.reload.status).to eq("processed")
    end

    it "never dead-letters a completed event or steals an active processing lease" do
      token = event.claim_processing!(signing_account_id: 123)
      event.fail_processing!
      expect(event.reload.status).to eq("received")
      event.finish_processing!(token)
      event.fail_processing!
      expect(event.reload.status).to eq("processed")
    end
  end
end
