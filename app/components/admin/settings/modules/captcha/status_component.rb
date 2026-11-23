# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Captcha
        # Customer-facing Captcha settings: provider status plus public-page
        # throttles. `pages` is an array of hashes from StatusController.
        class StatusComponent < ViewComponent::Base
          def initialize(settings:, module_enabled:, pages:, customer_id:)
            @settings       = settings
            @module_enabled = module_enabled
            @pages          = Array(pages)
            @customer_id    = customer_id
          end

          attr_reader :settings, :module_enabled, :pages, :customer_id

          def provider_name
            return I18n.t("captcha.platform_settings.none") if settings.nil?

            ::Captcha::Providers.for(settings.provider).display_name
          rescue ArgumentError
            I18n.t("settings_modules.captcha.provider_unavailable")
          end

          def configured?
            settings&.configured? || false
          end

          def empty? = pages.empty?

          def page_name(page) = page.fetch(:name).to_s
          def page_public_path(page) = page[:public_path].presence || "/#{customer_id}/page/#{page[:public_uuid]}"
          def page_launched?(page) = page[:launched] == true
          def page_toggle_url(page) = page.fetch(:update_url)
          def page_preset(page) = page[:preset] || ::Captcha::ThrottlePresets::PRESET_100_PER_5MIN

          def page_toggle_aria(page)
            I18n.t("captcha.throttle.aria", name: page_name(page))
          end
        end
      end
    end
  end
end
