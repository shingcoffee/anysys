# frozen_string_literal: true

module Admin
  # Persistent per-user mark-read of an admin-chrome bell notification.
  # Lives under /:cid/admin/ (tenant admin), not /admin/maintenance/platform/ —
  # every tenant admin must be able to POST it. RouteAuthorization already
  # requires admin_or_owner? on this prefix.
  class PlatformAnnouncementReadsController < ApplicationController
    def create
      announcement = readable_announcement
      if announcement
        PlatformAnnouncementRead.record!(
          announcement: announcement,
          user_id:      current_user.id,
          customer_id:  current_customer_id
        )
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: replace_bell_fragments }
        format.html { redirect_back fallback_location: admin_dashboard_path(current_customer_id) }
      end
    end

    private

    # Replaces the trigger, badge, and panel body independently. The
    # notifications-menu Stimulus root and the panel wrapper stay mounted so
    # the open dropdown is not remounted closed.
    def replace_bell_fragments
      bell = NotificationsButtonComponent.new
      [
        turbo_stream.replace(
          NotificationsBellTriggerComponent::DOM_ID,
          render_to_string(bell.trigger(expanded: true), layout: false)
        ),
        turbo_stream.replace(
          NotificationsBellBadgeComponent::DOM_ID,
          render_to_string(bell.badge, layout: false)
        ),
        turbo_stream.replace(
          NotificationsInboxComponent::PANEL_BODY_DOM_ID,
          render_to_string(
            NotificationsInboxComponent.new(
              items: bell.inbox_items,
              mark_read_path: admin_platform_announcement_reads_path(current_customer_id),
              support_ticket_read_path: admin_support_ticket_reads_path(current_customer_id)
            ),
            layout: false
          )
        ),
        turbo_stream.replace(
          Notifications::Stream::ANNOUNCEMENT_UNREAD_ID,
          Notifications::Stream.announcement_unread_html(bell.announcement_unread_count)
        )
      ]
    end

    # Only something the viewer can actually see in the bell inbox right now
    # may be marked read — this stops a forged / draft / other-tenant /
    # aged-out id from writing rows for unrelated announcements.
    def readable_announcement
      id = read_announcement_id
      return nil if id.blank? || current_user.blank?

      PlatformAnnouncements::InboxResolver
        .for_customer(current_customer_id)
        .announcements
        .find { |announcement| announcement.id.to_s == id }
    end

    def read_announcement_id
      raw = params[:platform_announcement_id]
      raw = params.dig(:platform_announcement_read, :platform_announcement_id) if raw.blank?
      raw.to_s.presence
    end
  end
end
