# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Payments
        # Customer-facing CRUD for the tenant's payment merchant accounts. One
        # row per (provider, mode); customers enable a gateway by setting the
        # row's status to "active". Vendor-specific credential keys come from
        # the gateway class' .credential_fields list — adding a new gateway
        # adds new fields here automatically with no controller changes.
        class MerchantAccountsController < ::Admin::Modules::Payments::BaseController
          dashboard_menu_item :settings
          SHARED_ATTRIBUTES = %i[provider mode merchant_id notify_url_override status].freeze

          before_action :set_account, only: %i[edit update test_connection]

          def index
            accounts = ::Payments::MerchantAccount.for_current_customer.order(:provider, :mode)
            # Build a hash keyed by provider string → the "representative" account for the
            # gallery tile. Priority: active row first, then sandbox, then first available.
            accounts_by_provider = accounts.group_by(&:provider).transform_values do |rows|
              rows.find { |r| r.enabled? } ||
                rows.find { |r| r.mode == "sandbox" } ||
                rows.first
            end
            available  = ::Payments::PlatformGateway.available_providers.map(&:to_s)
            gateways   = ::Payments::Gateways.all.select { |g| available.include?(g.key.to_s) }
            component  = ::Payments::Admin::GatewayGalleryComponent.new(
              gateways:             gateways,
              accounts_by_provider: accounts_by_provider,
              default_provider:     ::Payments::DefaultGateway.provider_for(current_customer.id)
            )
            # This page is always a full HTML document. When the gateway-config
            # form (edit) saves, Turbo submits with an `Accept:
            # text/vnd.turbo-stream.html` header that also rides along on the
            # post-redirect GET landing here. Without forcing html, Rails
            # content-negotiates to turbo_stream and labels this full-page
            # response as text/vnd.turbo-stream.html — Turbo then tries to apply
            # it as stream actions and injects the gallery as stray nodes (the
            # "junk cards"). Pinning the content type keeps it a normal Turbo
            # Drive page visit.
            respond_to do |format|
              format.html { render component }
              format.any  { render component, content_type: "text/html" }
            end
          end

          # GatewayConfigComponent requires a persisted account (it generates URLs
          # using account.id). Since the provisioner auto-seeds all MerchantAccount
          # rows when the Payments module is enabled, the manual "new" flow is an
          # edge case. Redirect to index so the admin uses the auto-seeded tiles.
          def new
            redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                        notice: t("admin_settings.flash.merchant_accounts.auto_provisioned")
          end

          def create
            return reject_unavailable_provider! unless platform_available?(account_params[:provider])

            @account = build_account_from_params
            if @account.save
              redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id)
            else
              # Re-render is not possible for unpersisted accounts with GatewayConfigComponent
              # (it requires account.id for URL generation). Redirect back with errors.
              redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                          alert: @account.errors.full_messages.to_sentence
            end
          end

          def edit
            render gateway_config_component(@account)
          end

          def update
            shared, vendor = split_params(@account.provider)
            # provider and mode define the row's identity (and its DB unique key).
            # They are never editable on an existing record — drop them so a
            # crafted PATCH can't re-point a Stripe row at Alipay, etc.
            shared = shared.except(:provider, :mode)
            # Only the activate transition is gated. Credential edits and
            # disable stay allowed so leftover rows can be wound down after
            # the platform owner turns the tender off.
            if shared[:status].to_s == "active" && !platform_available?(@account.provider)
              return reject_unavailable_provider!
            end

            @account.assign_attributes(shared)
            @account.write_credentials(vendor)
            if @account.save
              # The inline enable/disable toggle PATCHes via fetch and expects a
              # 2xx — a redirect would make fetch re-issue the PATCH to the
              # collection path (no PATCH route → 404) and the toggle reverts.
              respond_to do |format|
                format.json { head :no_content }
                format.html do
                  # 303 See Other so a Turbo form submission performs a GET visit
                  # to the gallery instead of re-issuing the PATCH to the new URL.
                  redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                              notice: t("admin_settings.flash.merchant_accounts.updated"), status: :see_other
                end
              end
            else
              respond_to do |format|
                format.json { render json: { errors: @account.errors.full_messages }, status: :unprocessable_entity }
                format.html do
                  render gateway_config_component(@account), status: :unprocessable_entity
                end
              end
            end
          end

          # POST /:cid/admin/settings/modules/payments/merchant_accounts/:id/test_connection
          #
          # Lightweight gateway connectivity check. Tenant-scoped via set_account
          # (which uses for_current_customer). Returns JSON { ok:, message:, verified_at:, verified_at_label: }.
          # Authorization: inherited require_admin_or_owner! from RouteAuthorization.
          def test_connection
            result = ::Payments::Gateway.test_connection(
              customer: current_customer,
              provider: @account.provider,
              mode:     @account.mode
            )
            verified = result[:verified_at]
            render json: {
              ok:                result[:ok],
              message:           result[:message],
              verified_at:       verified&.iso8601,
              verified_at_label: verified && I18n.l(verified, format: :long)
            }, status: result[:ok] ? :ok : :unprocessable_entity
          end

          private

          # Builds the per-gateway config view, supplying every (provider, mode)
          # row so the environment switcher can link directly to each row's edit
          # page (each mode is a distinct record with its own id).
          def gateway_config_component(account)
            siblings = ::Payments::MerchantAccount.for_current_customer
                                                  .where(provider: account.provider)
                                                  .index_by(&:mode)
            ::Payments::Admin::GatewayConfigComponent.new(account: account, accounts_by_mode: siblings)
          end

          def set_account
            @account = ::Payments::MerchantAccount.for_current_customer.find(params[:id])
          end

          # Gallery and provisioner already hide tenders the platform owner has
          # not opened. Create/activate must match that list — otherwise a
          # crafted POST/PATCH can stand up an active MerchantAccount for a
          # PSP the platform never offered, and CredentialResolver will charge
          # it (EligibleGateways only filters public checkout).
          def platform_available?(provider)
            return false if provider.blank?

            ::Payments::PlatformGateway.available_providers.map(&:to_s).include?(provider.to_s)
          end

          def reject_unavailable_provider!
            message = t("admin_settings.flash.merchant_accounts.not_platform_available")
            respond_to do |format|
              format.json { render json: { errors: [message] }, status: :unprocessable_entity }
              format.html do
                redirect_to admin_settings_modules_payments_merchant_accounts_path(current_customer_id),
                            alert: message
              end
            end
          end

          def build_account_from_params
            shared, vendor = split_params(account_params[:provider])
            acc = ::Payments::MerchantAccount.new(shared.merge(customer_id: current_customer.id))
            acc.write_credentials(vendor)
            acc
          end

          # Split the submitted params hash into shared (typed columns) and
          # blob-stored (JSON credentials) for the chosen gateway. default_currency
          # is non-vendor config but still lives in the credentials blob (AGENTS.md
          # forbids typed columns on payment_merchant_accounts), so it is routed to
          # the blob alongside the vendor credential keys.
          def split_params(provider)
            permitted = account_params
            blob_keys = (vendor_credential_keys(provider) + [:default_currency]).map(&:to_s)
            shared = permitted.slice(*SHARED_ATTRIBUTES).to_h.symbolize_keys
            blob   = permitted.slice(*blob_keys).to_h
            [shared, blob]
          end

          def vendor_credential_keys(provider)
            return [] unless provider.is_a?(String) && provider.present?
            ::Payments::Gateways.for(provider).credential_fields.map { |f| f[:name] }
          rescue ArgumentError
            []
          end

          def account_params
            submitted = params.require(:payment_merchant_account)
            provider = @account&.provider || submitted[:provider]
            submitted.permit(*SHARED_ATTRIBUTES, :default_currency, *vendor_credential_keys(provider))
          end
        end
      end
    end
  end
end
