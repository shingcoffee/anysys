# frozen_string_literal: true

module Platform
  # Full-bleed admin-shell stack of the live platform announcements for the
  # current tenant. Occupies normal column flow (not sticky) above ContextBanner.
  #
  # The wrapper element is rendered even when there is nothing to show: it is
  # the Turbo Stream target that a dismissal replaces, so it has to stay in the
  # DOM for the second dismissal to land.
  class AnnouncementBannerComponent < ApplicationComponent
    STACK_DOM_ID = "platform-announcements"

    # Only the top few are shown at once — a wall of stacked strips pushes the
    # whole admin shell off-screen. Dismissing one reveals the next.
    MAX_VISIBLE = 3

    SEVERITY_ORDER = { "critical" => 0, "warning" => 1, "info" => 2 }.freeze

    TITLE_LIMIT = 72
    BODY_LIMIT = 140

    SEVERITY_CHROME = {
      "info" => {
        strip_class: "border-l-[3px] border-info bg-info-subtle",
        icon_class:  "text-info",
        role:        "status",
        icon_path:   AlertComponent::TYPES[:info][:icon_path]
      },
      "warning" => {
        strip_class: "border-l-[3px] border-warning bg-warning-subtle",
        icon_class:  "text-warning",
        role:        "status",
        icon_path:   AlertComponent::TYPES[:warning][:icon_path]
      },
      "critical" => {
        strip_class: "border-l-[3px] border-danger bg-danger-subtle",
        icon_class:  "text-danger",
        role:        "alert",
        icon_path:   AlertComponent::TYPES[:error][:icon_path]
      }
    }.freeze

    def initialize(dismissed_ids: nil, user: nil, customer_id: nil)
      @dismissed_ids_override = dismissed_ids
      @user_override          = user
      @customer_id_override   = customer_id
    end

    def render?
      viewer_allowed?
    end

    # Highest severity first, then newest — a critical outage notice must not
    # sit below a chatty info notice published an hour later.
    def announcements
      @announcements ||= resolved.sort_by { |row| SEVERITY_ORDER.fetch(row.severity, 99) }
                                 .first(MAX_VISIBLE)
    end

    def body_for(announcement)
      announcement.body_for(I18n.locale)
    end

    def chrome_for(announcement)
      SEVERITY_CHROME.fetch(announcement.severity.to_s, SEVERITY_CHROME["info"])
    end

    def dom_id_for(announcement)
      "#{STACK_DOM_ID}-#{announcement.id}"
    end

    def dismiss_path
      helpers.admin_platform_announcement_dismissals_path(resolved_customer_id)
    end

    def stack_dom_id = STACK_DOM_ID

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

    def resolved
      @resolved ||=
        if @dismissed_ids_override.nil?
          PlatformAnnouncements::Resolver.for_viewer(user: viewer, customer_id: resolved_customer_id)
        else
          PlatformAnnouncements::Resolver.for_customer(
            resolved_customer_id, dismissed_ids: Array(@dismissed_ids_override)
          )
        end
    end
  end
end
