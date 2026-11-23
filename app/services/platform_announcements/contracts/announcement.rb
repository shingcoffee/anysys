# frozen_string_literal: true

require "reform/form"

module PlatformAnnouncements
  module Contracts
    class Announcement < Reform::Form
      # Prefix-only would accept `https://example.com\njavascript:alert(1)`.
      LINK_URL_FORMAT = /\Ahttps?:\/\/\S+\z/

      property :title
      property :body_en
      property :body_zh
      property :severity
      property :link_url
      property :status
      property :audience
      property :starts_at
      property :ends_at
      property :target_rules
      property :target_rules_malformed, virtual: true

      validates :title, presence: true, length: { maximum: 120 }
      validates :body_en, presence: true, length: { maximum: 500 }
      validates :body_zh, presence: true, length: { maximum: 500 }
      validates :severity, inclusion: { in: PlatformAnnouncement::SEVERITIES }
      validates :status, inclusion: { in: PlatformAnnouncement::STATUSES }
      validates :audience, inclusion: { in: PlatformAnnouncement::AUDIENCES }
      validates :link_url,
                length: { maximum: 2048 },
                format: { with: LINK_URL_FORMAT },
                allow_blank: true
      validate :link_url_is_http_uri
      validate :ends_at_after_starts_at
      validate :selected_audience_has_conditions

      private

      def link_url_is_http_uri
        return if link_url.blank?

        uri = URI.parse(link_url.to_s)
        return if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?

        errors.add(:link_url, :invalid)
      rescue URI::InvalidURIError
        errors.add(:link_url, :invalid)
      end

      def ends_at_after_starts_at
        return if starts_at.blank? || ends_at.blank?
        return if ends_at > starts_at

        errors.add(:ends_at, :greater_than, count: starts_at)
      end

      def selected_audience_has_conditions
        return unless audience.to_s == "selected"

        rules = PlatformAnnouncements::TargetRules.parse(target_rules)
        if target_rules_malformed || rules.malformed?
          errors.add(:base, I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
          return
        end

        unless rules.usable?
          errors.add(:base, I18n.t("maint_platform.announcements.form.errors.target_rules_blank"))
        end
      end
    end
  end
end
