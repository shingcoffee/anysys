# frozen_string_literal: true

module Captcha
  # Vendor widget for the public captcha challenge interstitial only.
  # Target pages and platform forms must not embed this component.
  class WidgetComponent < ViewComponent::Base
    def render?
      settings.present? && widget.present?
    end

    def stimulus_controller = widget[:stimulus_controller]
    def sdk_url             = widget[:sdk_url]
    def data_attrs          = widget[:data] || {}
    def show_hint?          = !settings.provider_class.invisible?

    private

    def settings
      return @settings if defined?(@settings)

      @settings = ::Captcha::ProviderSettings.active
    end

    def widget
      return nil if settings.nil?

      @widget ||= settings.provider_class.widget(settings)
    end
  end
end
