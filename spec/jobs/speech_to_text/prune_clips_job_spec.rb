# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::PruneClipsJob do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, customer: customer) }

  before do
    Current.customer = customer
    allow(SpeechToText::BroadcastResult).to receive(:call)
  end

  def create_clip(created_at:, updated_at: created_at, status: "pending")
    clip = create(:speech_to_text_clip, :with_audio, customer: customer, user: user, status: status)
    clip.update_columns(created_at: created_at, updated_at: updated_at)
    clip
  end

  it "terminalizes abandoned pending clips, purges audio, and keeps them pollable" do
    now = Time.zone.parse("2026-08-25 12:00:00")
    stale = create_clip(created_at: now - 16.minutes)
    fresh = create_clip(created_at: now - 5.minutes)

    described_class.perform_now(now: now)

    expect(stale.reload).to have_attributes(status: "failed", error_code: "generic_error")
    expect(stale.audio).not_to be_attached
    expect(SpeechToText::BroadcastResult).to have_received(:call).with(clip: stale)
    expect(SpeechToText::Clip.where(id: fresh.id)).to exist
  end

  it "recovers processing clips without stealing a recent claim" do
    now = Time.current
    stale = create_clip(created_at: now - 6.minutes, status: "processing")
    live = create_clip(created_at: now - 1.minute, status: "processing")
    described_class.perform_now(now: now)
    expect(stale.reload.status).to eq("failed")
    expect(stale.audio).not_to be_attached
    expect(live.reload.status).to eq("processing")
    expect(live.audio).to be_attached
  end

  it "keeps a pending clip exactly at the 15-minute boundary" do
    now = Time.zone.parse("2026-08-25 12:00:00")
    boundary = create_clip(created_at: now - 15.minutes)
    described_class.perform_now(now: now)
    expect(SpeechToText::Clip.where(id: boundary.id)).to exist
  end

  it "prunes by terminal age captured before audio purge touches the clip" do
    now = Time.zone.parse("2026-08-25 12:00:00")
    travel_to(now) do
      succeeded = create_clip(created_at: now - 1.day, updated_at: now - 16.minutes, status: "succeeded")
      fresh_failed = create_clip(created_at: now - 1.day, updated_at: now - 5.minutes, status: "failed")
      described_class.perform_now(now: now)
      expect(SpeechToText::Clip.where(id: succeeded.id)).not_to exist
      expect(SpeechToText::Clip.where(id: fresh_failed.id)).to exist
      expect(fresh_failed.reload.audio).not_to be_attached
    end
  end

  it "retains a terminal clip exactly at the retention boundary" do
    now = Time.current.change(usec: 0)
    boundary = create_clip(created_at: now - 1.day, updated_at: now - described_class::MAX_AGE, status: "succeeded")
    described_class.perform_now(now: now)
    expect(SpeechToText::Clip.where(id: boundary.id)).to exist
  end
end
