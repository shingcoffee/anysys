# frozen_string_literal: true

# A tenant admin marking a platform announcement as read in the bell inbox.
#
# Scoped by customer_id as well as user_id so the platform owner acting as
# several tenants acknowledges each tenant separately. customer_id is the
# tenant context of the read, not ownership of the announcement.
class PlatformAnnouncementRead < ApplicationRecord
  belongs_to :announcement,
             class_name:  "PlatformAnnouncement",
             foreign_key: :platform_announcement_id,
             inverse_of:  :reads

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
