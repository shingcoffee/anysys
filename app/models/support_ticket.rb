# frozen_string_literal: true

# Tenant-owned support ticket opened from the admin Help menu.
class SupportTicket < ApplicationRecord
  include TenantScoped

  STATUSES = %w[open resolved].freeze
  HISTORY_RETENTION = 7.days

  belongs_to :user, class_name: "Authentication::User"
  has_many :messages,
           class_name:  "SupportTicketMessage",
           inverse_of:  :support_ticket,
           dependent:   :destroy
  has_many :reads,
           class_name:  "SupportTicketRead",
           inverse_of:  :support_ticket,
           dependent:   :delete_all

  scope :newest_first, -> { order(last_message_at: :desc, id: :desc) }
  scope :open, -> { where(status: "open") }

  scope :inbox_visible, ->(now = Time.current) {
    retention = now - HISTORY_RETENTION
    where(status: "open").or(where(status: "resolved").where(arel_table[:last_message_at].gteq(retention)))
  }

  def open? = status == "open"

  def resolved? = status == "resolved"

  def latest_message
    messages.max_by { |row| [ row.created_at, row.id ] }
  end

  def thread_messages
    messages.includes(:user).with_attached_images.order(:created_at, :id)
  end

  # Unread for `user` when a counterpart message is newer than their
  # SupportTicketRead cursor (or they have no cursor yet).
  def unread_for?(user)
    return false if user.blank?

    cutoff = reads.find { |row| row.user_id == user.id }&.last_read_at
    counterpart = user.platform_owner? ? "requester" : "owner"
    unseen = messages.select { |msg| msg.author_role == counterpart }
    unseen = unseen.select { |msg| msg.created_at > cutoff } if cutoff
    unseen.any?
  end
end
