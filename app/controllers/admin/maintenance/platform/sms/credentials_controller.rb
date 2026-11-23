# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Sms
    # SMS vendor credentials — platform-wide config at
    #   /:customer_id/maintenance/platform/module_settings/sms/credentials
    # Matches captcha / STT / email: delivery assignment first, then a provider
    # switcher and per-environment show/edit cards.
    class CredentialsController < BaseCredentialsController
      include ::Sms::PlatformParameters
      manages_credentials model:       ::Sms::Credential,
                          activity:    ::Sms::Activities::SaveCredential,
                          registry:    ::Sms::Adapters,
                          flash_scope: "sms_credentials",
                          index_route: -> { admin_maintenance_platform_module_settings_sms_credentials_path(current_customer_id) }

      before_action :set_vendor_context

      def index
        @ui_mode = params[:section].to_s == "delivery" ? :edit_delivery : :show
      end

      def new
        @edit_mode_key = requested_mode
        existing = @credentials_by_mode[@edit_mode_key]
        if existing
          redirect_to edit_admin_maintenance_platform_module_settings_sms_credential_path(
            current_customer_id, existing
          ) and return
        end

        @credential = credential_model.new(provider: @provider_key, mode: @edit_mode_key, status: "disabled")
        @ui_mode = :edit_vendor
      end

      def edit
        @edit_mode_key = @credential.mode
        @ui_mode = :edit_vendor
      end

      def delivery
        result = ::Sms::Activities::AssignDelivery.call(
          sandbox_provider: params[:sandbox_provider],
          production_provider: params[:production_provider]
        )
        if result.success?
          redirect_to index_path, notice: t("maint_platform.flash.sms_credentials.delivery_updated")
        else
          @ui_mode = :edit_delivery
          @errors = result.errors
          render :index, status: :unprocessable_entity
        end
      end

      private

      def persist(flash_key)
        result = ::Sms::PlatformCredentialSave.call(record: @credential, params: credential_params)
        if result.success?
          redirect_to index_path(provider: result.model.provider),
                      status: :see_other, notice: t("maint_platform.flash.#{flash_scope}.#{flash_key}")
        else
          @edit_mode_key = @credential.mode.presence || requested_mode
          @ui_mode = :edit_vendor
          @provider_key = @credential.provider.presence || @provider_key
          refresh_credentials_by_mode
          yield
        end
      end

      def index_path(provider: nil)
        key = provider.presence || @credential&.provider || @provider_key
        admin_maintenance_platform_module_settings_sms_credentials_path(
          current_customer_id, provider: key
        )
      end

      def set_vendor_context
        keys = ::Sms::Adapters.keys.map(&:to_s)
        requested = params[:provider].presence ||
                    params.dig(:sms_credential, :provider) ||
                    @credential&.provider
        @all_credentials = credential_model.order(:id).to_a
        @provider_key = keys.include?(requested.to_s) ? requested.to_s : fallback_provider_key
        @providers = ::Sms::Adapters.all
        refresh_credentials_by_mode
        @delivery_by_mode = {
          "sandbox" => resolved_provider("sandbox"),
          "production" => resolved_provider("production")
        }
      end

      def refresh_credentials_by_mode
        @credentials_by_mode = @all_credentials.select { |c| c.provider == @provider_key }.index_by(&:mode)
      end

      def fallback_provider_key
        resolved_provider(::Sms::CredentialResolver.default_mode).presence ||
          ::Sms::Adapters.default_key.to_s
      end

      def resolved_provider(mode)
        default_key = ::Sms::Adapters.default_key.to_s
        active = @all_credentials.select { |c| c.mode == mode && c.status == "active" }
        (active.find { |c| c.provider == default_key } || active.min_by(&:id))&.provider
      end

      def requested_mode
        mode = params[:mode].presence || params.dig(:sms_credential, :mode)
        ::Sms::Credential::MODES.include?(mode.to_s) ? mode.to_s : "sandbox"
      end

      def credential_params
        config_keys = ::Sms::Adapters.all.flat_map { |a| a.config_fields.map { |f| f[:name] } }.uniq
        platform_attributes(:sms_credential,
                            allowed: %i[provider mode status access_key_id access_key_secret sender_rate_per_second] + config_keys.map(&:to_sym))
      end
    end
  end
end
end
end
