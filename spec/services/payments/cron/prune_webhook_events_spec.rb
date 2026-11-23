# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Cron::PruneWebhookEvents do
  def create_event(psp_event_id:, created_at:)
    event = create(:payment_webhook_event,
                   provider: "alipay", psp_event_id: psp_event_id, event_type: "trade.success",
                   status: "processed", payload: {})
    event.update_columns(created_at: created_at)
    event
  end

  it "deletes events older than the retention window and keeps newer ones" do
    now = Time.zone.parse("2026-07-13 00:00:00")
    old_event   = create_event(psp_event_id: "old-1", created_at: now - described_class::RETENTION - 1.day)
    edge_event  = create_event(psp_event_id: "edge-1", created_at: now - described_class::RETENTION + 1.hour)
    fresh_event = create_event(psp_event_id: "fresh-1", created_at: now - 1.day)

    described_class.perform(now: now)

    expect(Payments::WebhookEvent.where(id: old_event.id)).not_to exist
    expect(Payments::WebhookEvent.where(id: edge_event.id)).to exist
    expect(Payments::WebhookEvent.where(id: fresh_event.id)).to exist
  end

  it "defaults now: to the current time" do
    stale = create_event(psp_event_id: "stale-default-1", created_at: 91.days.ago)

    described_class.perform

    expect(Payments::WebhookEvent.where(id: stale.id)).not_to exist
  end
end
