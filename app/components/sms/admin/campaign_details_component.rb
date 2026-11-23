# frozen_string_literal: true

module Sms
  module Admin
    class CampaignDetailsComponent < BaseComponent
      attr_reader :campaign

      def initialize(campaign:, templates:, segments:, contacts:, preview:, report:, errors:)
        @campaign, @templates, @segments, @contacts = campaign, templates, segments, contacts
        @preview, @report, @errors = preview, report, errors || {}
      end

      def draft? = campaign.status == "draft"
      def launchable? = draft? && @preview && @preview[:review_token].present? && Array(@preview[:blockers]).empty?

      def settings
        draft? ? campaign.attributes.slice("name", "send_timing", "timezone", "quiet_hours_start", "quiet_hours_end", "frequency_window_hours", "send_rate_per_minute", "deadline_hours") : campaign.settings_snapshot
      end

      def audience_name
        if draft?
          return ui("campaigns.all_contacts") if campaign.segment_id.nil?

          @segments.find { |s| s[:id] == campaign.segment_id }&.dig(:name) || t("page_shortcuts.unavailable")
        else
          campaign.audience_snapshot["segment_name"].presence || ui("campaigns.all_contacts")
        end
      end

      def template_name
        if draft?
          @templates.find { |template| template[:id] == campaign.template_id }&.dig(:label) || t("sms_presentation.not_recorded")
        else
          campaign.settings_snapshot.dig("template", "key") || t("sms_presentation.not_recorded")
        end
      end
    end
  end
end
