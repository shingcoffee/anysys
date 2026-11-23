# frozen_string_literal: true

module Captcha
  class ThrottlePickerComponent < ViewComponent::Base
    SKIP_VALUE = "skip"

    def initialize(url:, extra_params: {}, preset:, limit_count: nil, period_minutes: nil,
                   aria_label: nil, skipped: false, include_skip: false, customer_context: false)
      @url = url
      @extra_params = extra_params
      @preset = preset.to_s.presence || Captcha::ThrottlePresets::PRESET_100_PER_5MIN
      @limit_count = limit_count
      @period_minutes = period_minutes
      @aria_label = aria_label
      @skipped = skipped
      @include_skip = include_skip
      @customer_context = customer_context
    end

    def include_skip? = @include_skip == true
    def customer_context? = @customer_context == true
    def skipped? = @skipped == true

    def custom?
      !skipped? && @preset == Captcha::ThrottlePresets::PRESET_CUSTOM
    end

    def display_label
      return option_label("skip") if include_skip? && skipped?
      return option_label(@preset) unless custom?
      return option_label("custom") if @limit_count.blank? || @period_minutes.blank?

      key = customer_context? ? "settings_modules.captcha.custom_rate" : "captcha.throttle.custom_rate"
      I18n.t(key, count: @limit_count, minutes: @period_minutes)
    end

    def select_value
      return SKIP_VALUE if include_skip? && skipped?

      @preset
    end

    def option_selected?(value)
      select_value.to_s == value.to_s
    end

    def rate_options
      [
        Captcha::ThrottlePresets::PRESET_5_PER_1MIN,
        Captcha::ThrottlePresets::PRESET_20_PER_1MIN,
        Captcha::ThrottlePresets::PRESET_100_PER_5MIN,
        Captcha::ThrottlePresets::PRESET_EVERY_HIT,
        Captcha::ThrottlePresets::PRESET_CUSTOM
      ]
    end

    def option_label(value)
      return I18n.t("captcha.throttle.presets.#{value}") unless customer_context?

      I18n.t("settings_modules.captcha.presets.#{value}", default: I18n.t("captcha.throttle.presets.#{value}"))
    end

    def field_dom_id(name)
      "captcha-throttle-#{name}-#{object_id}"
    end
  end
end
