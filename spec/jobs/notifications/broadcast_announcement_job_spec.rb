# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::BroadcastAnnouncementJob do
  it "broadcasts when the announcement is live" do
    notice = create(:platform_announcement, :published, :all_customers)
    allow(Notifications::Stream).to receive(:broadcast_announcement!)

    described_class.perform_now(notice.id)

    expect(Notifications::Stream).to have_received(:broadcast_announcement!).with(notice)
  end

  it "no-ops when the announcement is not live" do
    notice = create(:platform_announcement, :draft, :all_customers)
    allow(Notifications::Stream).to receive(:broadcast_announcement!)

    described_class.perform_now(notice.id)

    expect(Notifications::Stream).not_to have_received(:broadcast_announcement!)
  end

  it "enqueues at starts_at for a scheduled announcement" do
    starts = 1.hour.from_now.change(usec: 0)
    notice = create(:platform_announcement, :published, :all_customers, starts_at: starts)

    expect {
      described_class.schedule(notice)
    }.to have_enqueued_job(described_class).with(notice.id).at(starts)
  end

  it "does not enqueue when the announcement is already live" do
    notice = create(:platform_announcement, :published, :all_customers)

    expect {
      described_class.schedule(notice)
    }.not_to have_enqueued_job(described_class)
  end
end
