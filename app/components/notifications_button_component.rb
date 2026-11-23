# frozen_string_literal: true

# Admin-topbar bell. The Stimulus root wraps the trigger, badge, and panel
# and is never turbo-replaced. Mark-read streams replace #notifications-trigger,
# #notifications-badge, #notifications-panel-body, and the announcement-unread
# counter. Help broadcasts replace only #notifications-support-ticket-unread plus the
# help row — never the URL-tenant announcement rows.
class NotificationsButtonComponent < ApplicationComponent
  def initialize(user: nil, customer_id: nil)
    @user_override        = user
    @customer_id_override = customer_id
  end

  def trigger(expanded: false)
    NotificationsBellTriggerComponent.new(aria_label: trigger_aria_label, expanded: expanded)
  end

  def badge
    NotificationsBellBadgeComponent.new(count: unread_count, label: badge_label)
  end

  def inbox
    NotificationsInboxComponent.new(
      items: inbox_items,
      mark_read_path: mark_read_path,
      support_ticket_read_path: support_ticket_read_path
    )
  end

  def trigger_aria_label
    if unread_count.positive?
      I18n.t("chrome.notifications.unread_titled", count: unread_count)
    else
      I18n.t("chrome.notifications.title")
    end
  end

  def unread_count
    announcement_unread_count + support_ticket_unread_count
  end

  def announcement_unread_count
    inbox_items.count { |item| item.kind == :announcement && item.unread }
  end

  def support_ticket_unread_count
    inbox_items.count { |item| item.kind == :support_ticket && item.unread }
  end

  def stream_name
    return if viewer.blank? || !viewer_allowed?

    Notifications::Stream.name(user_id: viewer.id)
  end

  def support_ticket_unread_html
    Notifications::Stream.support_ticket_unread_html(support_ticket_unread_count)
  end

  def announcement_unread_html
    Notifications::Stream.announcement_unread_html(announcement_unread_count)
  end

  def badge_label
    unread_count >= 100 ? I18n.t("chrome.notifications.unread_overflow") : unread_count.to_s
  end

  def inbox_items
    @inbox_items ||= begin
      return [] unless viewer_allowed? && resolved_customer_id.present?

      Notifications::Inbox.for_viewer(user: viewer, customer_id: resolved_customer_id)
    end
  end

  def mark_read_path
    return if resolved_customer_id.blank?

    helpers.admin_platform_announcement_reads_path(resolved_customer_id)
  end

  def support_ticket_read_path
    return if resolved_customer_id.blank?

    helpers.admin_support_ticket_reads_path(resolved_customer_id)
  end

  private

  def viewer_allowed?
    viewer.present? && (viewer.admin? || viewer.platform_owner?)
  end

  def viewer
    @user_override || Current.user
  end

  def resolved_customer_id
    @customer_id_override || Current.customer_id
  end
end
