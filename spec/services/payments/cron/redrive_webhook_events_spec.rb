# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Cron::RedriveWebhookEvents do
  def create_event(psp_event_id:, status:, created_at:, updated_at: created_at, signing_merchant_id: "M1")
    event = create(:payment_webhook_event,
                   provider: "alipay", psp_event_id: psp_event_id, event_type: "trade.success",
                   status: status, signing_merchant_id: signing_merchant_id,
                   payload: Payments::WebhookEvent.payload_with_verification({}, signing_account_id: 777))
    event.update_columns(created_at: created_at, updated_at: updated_at)
    event
  end

  let(:now) { Time.zone.parse("2026-07-13 12:00:00") }

  describe "stuck 'received' events" do
    it "re-enqueues a 'received' event stuck beyond the grace period" do
      stuck = create_event(psp_event_id: "stuck-1", status: "received",
                           created_at: now - 1.hour, updated_at: now - described_class::RECEIVED_GRACE - 1.minute)

      expect {
        described_class.perform(now: now)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob).with(stuck.id, "M1", 777)

      expect(stuck.reload.status).to eq("received")
    end

    it "does not touch a 'received' event still inside the grace period (job may still be retrying)" do
      fresh = create_event(psp_event_id: "fresh-1", status: "received",
                           created_at: now, updated_at: now - described_class::RECEIVED_GRACE + 1.minute)

      expect {
        described_class.perform(now: now)
      }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)

      expect(fresh.reload.status).to eq("received")
    end
  end

  describe "dead-lettered 'failed' events" do
    it "re-enqueues a 'failed' event whose last attempt is older than the redrive interval" do
      failed = create_event(psp_event_id: "failed-1", status: "failed",
                            created_at: now - 1.day,
                            updated_at: now - described_class::FAILED_REDRIVE_INTERVAL - 1.minute)

      expect {
        described_class.perform(now: now)
      }.to have_enqueued_job(Payments::ProcessWebhookEventJob).with(failed.id, "M1", 777)

      expect(failed.reload.status).to eq("received")
    end

    it "does not re-drive a 'failed' event redriven more recently than the redrive interval" do
      recently_redriven = create_event(psp_event_id: "failed-recent-1", status: "failed",
                                       created_at: now - 1.day,
                                       updated_at: now - described_class::FAILED_REDRIVE_INTERVAL + 1.minute)

      expect {
        described_class.perform(now: now)
      }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)

      expect(recently_redriven.reload.status).to eq("failed")
    end

    it "gives up on a 'failed' event older than FAILED_MAX_AGE, even if otherwise eligible" do
      ancient = create_event(psp_event_id: "ancient-1", status: "failed",
                             created_at: now - described_class::FAILED_MAX_AGE - 1.day,
                             updated_at: now - described_class::FAILED_REDRIVE_INTERVAL - 1.day)

      expect {
        described_class.perform(now: now)
      }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)

      expect(ancient.reload.status).to eq("failed")
    end
  end

  it "does not touch already 'processed' events" do
    processed = create_event(psp_event_id: "processed-1", status: "processed",
                             created_at: now - 30.days, updated_at: now - 30.days)

    expect {
      described_class.perform(now: now)
    }.not_to have_enqueued_job(Payments::ProcessWebhookEventJob)

    expect(processed.reload.status).to eq("processed")
  end

  it "continues past a single event that errors on redrive" do
    stuck1 = create_event(psp_event_id: "err-1", status: "received",
                          created_at: now - 1.hour, updated_at: now - described_class::RECEIVED_GRACE - 1.minute)
    stuck2 = create_event(psp_event_id: "err-2", status: "received",
                          created_at: now - 1.hour, updated_at: now - described_class::RECEIVED_GRACE - 1.minute)
    allow(Payments::ProcessWebhookEventJob).to receive(:perform_later)
      .with(stuck1.id, "M1", 777).and_raise(StandardError, "queue down")
    allow(Payments::ProcessWebhookEventJob).to receive(:perform_later).with(stuck2.id, "M1", 777)

    expect { described_class.perform(now: now) }.not_to raise_error

    expect(Payments::ProcessWebhookEventJob).to have_received(:perform_later).with(stuck2.id, "M1", 777)
    expect(stuck1.reload.updated_at).to eq(now - described_class::RECEIVED_GRACE - 1.minute)
  end

  it "defaults now: to the current time" do
    stuck = create_event(psp_event_id: "default-now-1", status: "received",
                         created_at: 1.hour.ago, updated_at: described_class::RECEIVED_GRACE.ago - 1.minute)

    described_class.perform

    expect(stuck.reload.status).to eq("received")
  end
end
