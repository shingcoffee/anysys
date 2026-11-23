# frozen_string_literal: true

module Admin
  # Persistent per-user dismissal of the admin-chrome announcement banner.
  # Lives under /:cid/admin/ (tenant admin), not /admin/maintenance/platform/ —
  # every tenant admin must be able to POST it. RouteAuthorization already
  # requires admin_or_owner? on this prefix.
  class PlatformAnnouncementDismissalsController < ApplicationController
    dashboard_menu_item :maintenance

    def create
      announcement = dismissible_announcement
      if announcement
        PlatformAnnouncementDismissal.record!(
          announcement: announcement,
          user_id:      current_user.id,
          customer_id:  current_customer_id
        )
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: replace_banner_stack }
        format.html { redirect_back fallback_location: admin_dashboard_path(current_customer_id) }
      end
    end

    private

    # Re-renders the whole stack rather than removing one strip, so the next
    # queued announcement slides up into the freed slot immediately.
    def replace_banner_stack
      turbo_stream.replace(
        Platform::AnnouncementBannerComponent::STACK_DOM_ID,
        render_to_string(Platform::AnnouncementBannerComponent.new, layout: false)
      )
    end

    # Only something the viewer can actually see right now may be dismissed —
    # this stops a forged id from writing rows for unrelated announcements.
    def dismissible_announcement
      id = dismissal_announcement_id
      return nil if id.blank? || current_user.blank?

      PlatformAnnouncements::Resolver
        .for_customer(current_customer_id)
        .find { |announcement| announcement.id.to_s == id }
    end

    def dismissal_announcement_id
      raw = params[:platform_announcement_id]
      raw = params.dig(:platform_announcement_dismissal, :platform_announcement_id) if raw.blank?
      raw.to_s.presence
    end
  end
end
