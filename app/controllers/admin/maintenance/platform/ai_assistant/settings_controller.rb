# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module AiAssistant
    # Platform-owner CRUD for AI Assistant provider credentials + tunables,
    # and the active-provider selection. Path-based platform-owner gating
    # happens via RouteAuthorization for any controller_path starting with
    # admin/maintenance/platform/.
    class SettingsController < ApplicationController
      dashboard_menu_item :maintenance

      before_action :set_provider_key
      before_action :set_settings
      before_action :set_feature_module
      before_action :set_section_mode, only: [ :edit, :update ]

      def show; end
      def edit; end

      def update
        result = ::AiAssistant::Activities::UpdateProviderSettings.call(
          provider: @provider_key, params: settings_params
        )
        if result.success?
          redirect_to settings_path(@provider_key),
                      notice: I18n.t("ai_assistant.platform_settings.flash.updated")
        else
          @errors = result.errors
          render :edit, status: :unprocessable_entity
        end
      end

      def test_connection
        result = ::AiAssistant::Activities::TestConnection.call(settings: @settings)
        if result.ok?
          redirect_to settings_path(@provider_key), notice: I18n.t("ai_assistant.platform_settings.test.ok")
        else
          redirect_to settings_path(@provider_key), alert: test_failure_message(result)
        end
      end

      private

      def test_failure_message(result)
        summary = I18n.t("ai_assistant.platform_settings.test.#{result.status}")
        return summary if result.message.blank?

        I18n.t("ai_assistant.platform_settings.test.failed_detail", summary: summary, message: result.message)
      end

      def set_provider_key
        keys = ::AiAssistant::Providers.keys.map(&:to_s)
        requested = params[:provider].to_s
        @provider_key =
          if keys.include?(requested)
            requested
          else
            ::AiAssistant::ProviderSettings.active_for(:generation)&.provider ||
              ::AiAssistant::ProviderSettings.active_for(:transcribe)&.provider ||
              ::AiAssistant::Providers.default_key.to_s
          end
      end

      def set_settings
        @settings             = ::AiAssistant::ProviderSettings.for_provider(@provider_key)
        @providers            = ::AiAssistant::Providers.keys.map { |k| ::AiAssistant::Providers.for(k) }
        @transcribe_settings  = ::AiAssistant::ProviderSettings.find_by(transcribe_active: true)
        @generation_settings  = ::AiAssistant::ProviderSettings.find_by(generation_active: true)
        @transcribe_key       = @transcribe_settings&.provider
        @generation_key       = @generation_settings&.provider
      end

      def set_feature_module
        @feature_module = FeatureModules::Module.find_by(key: "ai_assistant")
      end

      def set_section_mode
        @mode = params[:section].to_s == "jobs" ? :edit_jobs : :edit_vendor
      end

      def settings_path(provider_key)
        base = "/#{current_customer.id}/admin/maintenance/platform/module_settings/ai_assistant/settings"
        "#{base}?provider=#{provider_key}"
      end

      def settings_params
        provider_class = ::AiAssistant::Providers.for(@provider_key)
        config_keys = provider_class.config_fields.map { |f| f[:name].to_sym }
        params.require(:ai_assistant_provider_settings)
              .permit(:api_key, :transcribe_active, :generation_active,
                      :transcribe_assignee, :generation_assignee, *config_keys)
      end
    end
  end
end
end
end
