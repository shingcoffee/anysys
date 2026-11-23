# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::ExpireAnnouncementJob do
  let(:now) { Time.zone.parse("2026-10-11 12:00:00") }
  let(:ends_at) { now + 1.hour }
  let(:notice) { create(:platform_announcement, :published, ends_at: ends_at) }

  before { allow(Notifications::Stream).to receive(:refresh_announcement!) }

  it "schedules expiry for a live or future published notice at its exact end" do
    travel_to(now) do
      expect { Notifications::BroadcastAnnouncementJob.schedule(notice) }
        .to have_enqueued_job(described_class).with(notice.id, ends_at.iso8601(6)).at(ends_at)
    end
  end

  it "refreshes the existing stream at the current window's end" do
    notice
    travel_to(ends_at) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }
    expect(Notifications::Stream).to have_received(:refresh_announcement!).with(notice)
  end

  it "ignores a stale expiry after the owner extends the current window" do
    notice.update!(ends_at: ends_at + 2.hours)
    travel_to(ends_at) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }
    expect(Notifications::Stream).not_to have_received(:refresh_announcement!)
  end

  it "does not expire a current notice before its stored end" do
    notice
    travel_to(now) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }
    expect(Notifications::Stream).not_to have_received(:refresh_announcement!)
  end

  it "ignores draft, discarded, open-ended and destroyed current state" do
    notice.update!(status: "draft")
    travel_to(ends_at) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }
    notice.update!(status: "published", deleted_at: now)
    travel_to(ends_at) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }
    notice.update!(deleted_at: nil, ends_at: nil)
    travel_to(ends_at) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }
    notice.destroy!
    travel_to(ends_at) { described_class.perform_now(notice.id, ends_at.iso8601(6)) }

    expect(Notifications::Stream).not_to have_received(:refresh_announcement!)
  end

  it "does not schedule expiry for an unpublished, already-ended or unbounded notice" do
    travel_to(now) do
      [
        create(:platform_announcement, :draft, ends_at: ends_at),
        create(:platform_announcement, :published, ends_at: now),
        create(:platform_announcement, :published)
      ].each do |record|
        expect { described_class.schedule(record) }.not_to have_enqueued_job(described_class)
      end
    end
  end
end
