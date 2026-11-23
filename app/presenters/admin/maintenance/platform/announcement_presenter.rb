# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # View-facing formatting for a platform announcement: badges, audience
      # wording, timestamps. Keeps the controller free of presentation logic
      # and gives the index/show/table columns one shared vocabulary.
      class AnnouncementPresenter
        SEVERITY_VARIANTS  = { "info" => :info, "warning" => :warning, "critical" => :danger }.freeze
        STATUS_VARIANTS    = { "draft" => :default, "published" => :success }.freeze
        LIFECYCLE_VARIANTS = { draft: :default, scheduled: :info, live: :success, ended: :default }.freeze

        def initialize(announcement)
          @announcement = announcement
        end

        attr_reader :announcement

        def severity_badge
          {
            variant: SEVERITY_VARIANTS.fetch(announcement.severity, :default),
            label:   I18n.t("maint_platform.announcements.severities.#{announcement.severity}",
                            default: announcement.severity.to_s)
          }
        end

        def status_badge
          {
            variant: STATUS_VARIANTS.fetch(announcement.status, :default),
            label:   I18n.t("common.status.#{announcement.status}")
          }
        end

        def lifecycle_badge(now: Time.current)
          state = announcement.lifecycle(now: now)
          {
            variant: LIFECYCLE_VARIANTS.fetch(state, :default),
            label:   I18n.t("maint_platform.announcements.lifecycle.#{state}")
          }
        end

        # Deliberately count-free: rendering this per index row would run a full
        # segment COUNT for every row on the page. The exact figure lives on the
        # detail page, where a single count is cheap.
        def audience_label
          if announcement.all_customers?
            I18n.t("maint_platform.announcements.audience.all")
          else
            I18n.t("maint_platform.announcements.audience.selected")
          end
        end

        def link_url = announcement.link_url.presence

        def starts_at = format_datetime(announcement.starts_at)
        def ends_at   = format_datetime(announcement.ends_at)
        def created_at = format_datetime(announcement.created_at)
        def updated_at = format_datetime(announcement.updated_at)

        private

        def format_datetime(value)
          return I18n.t("common.labels.em_dash") if value.blank?

          I18n.l(value, format: :long)
        end
      end
    end
  end
end
