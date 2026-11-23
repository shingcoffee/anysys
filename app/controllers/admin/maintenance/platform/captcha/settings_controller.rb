# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Captcha
    # Platform-owner CRUD for captcha provider credentials + tunables, and the
    # active-provider selection. Path-based platform-owner gating happens via
    # RouteAuthorization for any controller_path starting with
    # admin/maintenance/platform/.
    class SettingsController < ApplicationController
      dashboard_menu_item :maintenance

      before_action :set_provider_key
      before_action :set_settings
      before_action :set_section_mode, only: [ :edit, :update ]

      def show; end
      def edit; end

      def update
        result = ::Captcha::Activities::UpdateProviderSettings.call(
          provider: @provider_key, params: settings_params
        )
        if result.success?
          redirect_to settings_path(@provider_key),
                      notice: I18n.t("captcha.platform_settings.flash.updated")
        else
          @errors = result.errors
          render :edit, status: :unprocessable_entity
        end
      end

      def test_connection
        result = ::Captcha::Activities::TestConnection.call(settings: @settings)
        flash_key = result.ok? ? :notice : :alert
        redirect_to settings_path(@provider_key),
                    flash_key => I18n.t("captcha.platform_settings.test.#{result.status}")
      end

      private

      def set_provider_key
        keys = ::Captcha::Providers.keys.map(&:to_s)
        requested = params[:provider].to_s
        @provider_key =
          if keys.include?(requested)
            requested
          else
            ::Captcha::ProviderSettings.active&.provider || ::Captcha::Providers.default_key.to_s
          end
      end

      def set_settings
        @settings    = ::Captcha::ProviderSettings.for_provider(@provider_key)
        @providers   = ::Captcha::Providers.keys.map { |k| ::Captcha::Providers.for(k) }
        @active_key  = ::Captcha::ProviderSettings.where(enabled: true).pick(:provider)
      end

      def set_section_mode
        @mode = params[:section].to_s == "active" ? :edit_active : :edit_vendor
      end

      def settings_path(provider_key)
        base = "/#{current_customer.id}/admin/maintenance/platform/module_settings/captcha/settings"
        "#{base}?provider=#{provider_key}"
      end

      def settings_params
        provider_class = ::Captcha::Providers.for(@provider_key)
        config_keys = provider_class.config_fields.map { |f| f[:name].to_sym }
        params.require(:captcha_provider_settings)
              .permit(:access_key_id, :access_key_secret, :enabled, :fail_policy,
                      :score_threshold, :active_assignee, *config_keys)
      end
    end
  end
end
end
end
