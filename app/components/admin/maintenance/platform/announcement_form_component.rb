# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # New/edit form for a platform announcement (owner, platform prefix).
      #
      # The Audience card mounts `platform-announcement-audience` so the
      # All / Selected radios can hide the condition builder (the builder
      # root is `panel`). Conditions reuse Emails::Audience::SegmentBuilderComponent.
      class AnnouncementFormComponent < ApplicationComponent
        TargetRulesSource = Struct.new(:segment_rules)

        def initialize(announcement:, customer_id:)
          @announcement = announcement
          @customer_id = customer_id.to_s
        end

        attr_reader :announcement, :customer_id

        def form_url
          if announcement.persisted?
            helpers.admin_maintenance_platform_announcement_path(customer_id, announcement)
          else
            helpers.admin_maintenance_platform_announcements_path(customer_id)
          end
        end

        def form_method
          announcement.persisted? ? :patch : :post
        end

        def index_path
          helpers.admin_maintenance_platform_announcements_path(customer_id)
        end

        def submit_label
          if announcement.persisted?
            I18n.t("maint_platform.announcements.form.update")
          else
            I18n.t("maint_platform.announcements.form.create")
          end
        end

        def severity_options
          PlatformAnnouncement::SEVERITIES.map do |severity|
            [I18n.t("maint_platform.announcements.severities.#{severity}"), severity]
          end
        end

        def status_options
          PlatformAnnouncement::STATUSES.map do |status|
            [I18n.t("common.status.#{status}"), status]
          end
        end

        def selected_audience?
          announcement.audience.to_s == "selected"
        end

        def target_rules_source
          TargetRulesSource.new(announcement.target_rules.presence || {})
        end

        def customer_field_catalog
          ::PlatformAnnouncements::CustomerFieldCatalog.new
        end

        def audience_preview_url
          helpers.audience_preview_admin_maintenance_platform_announcements_path(customer_id)
        end

        def target_rules_param_name
          "platform_announcement[target_rules_json]"
        end

        # Hung on the segment builder's hidden JSON field so the audience
        # controller can read the live rules without knowing its markup.
        def target_rules_output_data
          { "platform-announcement-audience-target" => "rules" }
        end
      end
    end
  end
end
