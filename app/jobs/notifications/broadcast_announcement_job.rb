# frozen_string_literal: true

module Notifications
  # Delivers a live announcement over the per-user Turbo Stream. Used when
  # the owner schedules a starts_at in the future: Save enqueues this to
  # run at that instant. Live saves broadcast inline and do not need the job.
  class BroadcastAnnouncementJob < ApplicationJob
    queue_as :default

    def self.schedule(announcement)
      ExpireAnnouncementJob.schedule(announcement)
      return unless announcement.scheduled?
      return if announcement.starts_at.blank?

      set(wait_until: announcement.starts_at).perform_later(announcement.id)
    end

    def perform(announcement_id)
      announcement = PlatformAnnouncement.kept.find_by(id: announcement_id)
      return if announcement.blank? || !announcement.live?

      Stream.broadcast_announcement!(announcement)
    end
  end
end
