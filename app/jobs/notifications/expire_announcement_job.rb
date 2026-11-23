# frozen_string_literal: true

require "time"

module Notifications
  # Refresh the existing signed notification stream at the end of a window.
  # A stale scheduled job cannot expire a notice whose end/state changed.
  class ExpireAnnouncementJob < ApplicationJob
    queue_as :default

    def self.schedule(announcement)
      return unless announcement.deleted_at.nil? && announcement.status == "published" &&
        announcement.ends_at.present? && announcement.ends_at > Time.current

      set(wait_until: announcement.ends_at).perform_later(announcement.id, announcement.ends_at.iso8601(6))
    end

    def perform(announcement_id, expected_ends_at)
      announcement = PlatformAnnouncement.kept.find_by(id: announcement_id)
      return unless announcement

      announcement.with_lock do
        return unless announcement.deleted_at.nil? && announcement.status == "published" &&
          announcement.ends_at == Time.iso8601(expected_ends_at) && announcement.ended?

        Stream.refresh_announcement!(announcement)
      end
    end
  end
end
