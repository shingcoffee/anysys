# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Emails
    # Email vendor credentials — platform-wide config at
    #   /:customer_id/maintenance/platform/module_settings/email/credentials
    # (AGENTS.md module category d). The page matches captcha / speech-to-text:
    # delivery assignment first, then a provider switcher and per-environment
    # show/edit cards. Create/update still go through SaveCredential.
    class CredentialsController < BaseCredentialsController
      manages_credentials model:       ::Emails::Credential,
                          activity:    ::Email::Activities::SaveCredential,
                          registry:    ::Email::Providers,
                          flash_scope: "emails_credentials",
                          index_route: -> { admin_maintenance_platform_module_settings_email_credentials_path(current_customer_id) }

      before_action :set_vendor_context

      def index
        @ui_mode = params[:section].to_s == "delivery" ? :edit_delivery : :show
      end

      def new
        @edit_mode_key = requested_mode
        existing = @credentials_by_mode[@edit_mode_key]
        if existing
          redirect_to edit_admin_maintenance_platform_module_settings_email_credential_path(
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
        result = ::Email::Activities::AssignDelivery.call(
          sandbox_provider: params[:sandbox_provider],
          production_provider: params[:production_provider]
        )
        if result.success?
          redirect_to index_path, notice: t("maint_platform.flash.emails_credentials.delivery_updated")
        else
          @ui_mode = :edit_delivery
          @errors = result.errors
          render :index, status: :unprocessable_entity
        end
      end

      private

      def persist(flash_key)
        result = save_activity.call(record: @credential, params: credential_params)
        if result.success?
          redirect_to index_path(provider: result.model.provider),
                      notice: t("maint_platform.flash.#{flash_scope}.#{flash_key}")
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
        admin_maintenance_platform_module_settings_email_credentials_path(
          current_customer_id, provider: key
        )
      end

      def set_vendor_context
        keys = ::Email::Providers.keys.map(&:to_s)
        requested = params[:provider].presence ||
                    params.dig(:emails_credential, :provider) ||
                    @credential&.provider
        @all_credentials = credential_model.order(:id).to_a
        @provider_key = keys.include?(requested.to_s) ? requested.to_s : fallback_provider_key
        @providers = ::Email::Providers.all
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
        resolved_provider(::Email::CredentialResolver.default_mode).presence ||
          ::Email::Providers.default_key.to_s
      end

      def resolved_provider(mode)
        default_key = ::Email::Providers.default_key.to_s
        active = @all_credentials.select { |c| c.mode == mode && c.status == "active" }
        (active.find { |c| c.provider == default_key } || active.min_by(&:id))&.provider
      end

      def requested_mode
        mode = params[:mode].presence || params.dig(:emails_credential, :mode)
        ::Emails::Credential::MODES.include?(mode.to_s) ? mode.to_s : "sandbox"
      end

      def credential_params
        config_keys = ::Email::Providers.all.flat_map { |p| p.config_fields.map { |f| f[:name] } }.uniq
        params.require(:emails_credential).permit(
          :provider, :host, :port, :username, :password, :authentication,
          :enable_starttls, :ssl, :domain, :mode, :status,
          :dkim_enabled, :dkim_domain, :dkim_selector, :dkim_private_key, :webhook_secret, *config_keys
        )
      end
    end
  end
end
end
end
