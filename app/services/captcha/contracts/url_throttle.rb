# frozen_string_literal: true

require "reform/form"

module Captcha
  module Contracts
    class UrlThrottle < Reform::Form
      property :match_kind, virtual: true
      property :url_pattern, virtual: true
      property :preset, virtual: true
      property :limit_count, virtual: true
      property :period_minutes, virtual: true
      property :customer_id, virtual: true
      property :surface_key, virtual: true
      property :page, virtual: true
      property :skipped, virtual: true

      validates :match_kind, inclusion: { in: Captcha::UrlThrottle::MATCH_KINDS }
      validates :url_pattern, presence: true
      validates :preset, inclusion: { in: Captcha::ThrottlePresets::KEYS }
      validate :custom_bounds

      private

      def custom_bounds
        return unless preset.to_s == Captcha::ThrottlePresets::PRESET_CUSTOM

        limit = Integer(limit_count, exception: false)
        minutes = Integer(period_minutes, exception: false)
        if limit.nil? || limit < Captcha::ThrottlePresets::MIN_CUSTOM_LIMIT || limit > Captcha::ThrottlePresets::MAX_CUSTOM_LIMIT
          errors.add(:limit_count, I18n.t("captcha.throttle.errors.limit_count"))
        end
        if minutes.nil? || minutes < Captcha::ThrottlePresets::MIN_CUSTOM_PERIOD_MINUTES || minutes > Captcha::ThrottlePresets::MAX_CUSTOM_PERIOD_MINUTES
          errors.add(:period_minutes, I18n.t("captcha.throttle.errors.period_minutes"))
        end
      end
    end
  end
end
