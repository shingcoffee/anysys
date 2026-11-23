# frozen_string_literal: true

# A tenant admin acknowledging a platform announcement banner.
#
# Persisted rather than kept in the session: a session-scoped dismissal
# resurrects the banner in every new session, browser, and device, which reads
# as a bug to the admin. Scoped by customer_id as well as user_id so the
# platform owner acting as several tenants acknowledges each tenant separately.
class PlatformAnnouncementDismissal < ApplicationRecord
  belongs_to :announcement,
             class_name:  "PlatformAnnouncement",
             foreign_key: :platform_announcement_id,
             inverse_of:  :dismissals

  belongs_to :user, class_name: "Authentication::User"
  belongs_to :customer

  # Idempotent: a double submit (or two tabs) must not raise.
  def self.record!(announcement:, user_id:, customer_id:)
    create!(announcement: announcement, user_id: user_id, customer_id: customer_id)
  rescue ActiveRecord::RecordNotUnique
    find_by(platform_announcement_id: announcement.id, user_id: user_id, customer_id: customer_id)
  end

  def self.announcement_ids_for(user_id:, customer_id:)
    return [] if user_id.blank? || customer_id.blank?

    where(user_id: user_id, customer_id: customer_id).pluck(:platform_announcement_id)
  end
end
