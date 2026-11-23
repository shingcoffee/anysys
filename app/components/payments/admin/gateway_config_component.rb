# frozen_string_literal: true

module Payments
  module Admin
    # Per-gateway configuration form. Renders the full edit surface for a
    # single Payments::MerchantAccount row: environment switcher (Sandbox /
    # Production), status toggle, vendor credential fields (via
    # CredentialFieldsComponent), static fields (merchant_id, notify_url,
    # default_currency), a Test Connection button, and form actions.
    #
    # The form method is always PATCH because every MerchantAccount row is
    # auto-seeded by the provisioner when the Payments module is enabled.
    class GatewayConfigComponent < ApplicationComponent
      attr_reader :account, :accounts_by_mode

      # accounts_by_mode: { "sandbox" => MerchantAccount, "production" => ... }
      # for the environment switcher. Each (provider, mode) is a distinct row with
      # its own id, so the switcher links to that row's edit page — there is no
      # `show` route and no `?mode=` query. Defaults to just the current account's
      # mode when callers don't supply siblings.
      def initialize(account:, accounts_by_mode: nil)
        @account          = account
        @accounts_by_mode = (accounts_by_mode || { account.mode.to_s => account }).transform_keys(&:to_s)
      end

      # Tabs for the Sandbox / Production switcher. Each tab links to the edit
      # page of that mode's MerchantAccount row (when it exists).
      def mode_tabs
        ::Payments::MerchantAccount::MODES.map do |mode|
          row = accounts_by_mode[mode]
          {
            mode:   mode,
            label:  t("settings_modules.payments.environments.#{mode}"),
            active: account.mode.to_s == mode,
            url:    (row && edit_url_for(row))
          }
        end
      end

      def gateway
        @gateway ||= ::Payments::Gateways.for(account.provider)
      rescue ArgumentError
        nil
      end

      def form_url
        helpers.admin_settings_modules_payments_merchant_account_path(
          customer_id: helpers.params[:customer_id],
          id: account.id
        )
      end

      def cancel_url
        helpers.admin_settings_modules_payments_merchant_accounts_path(
          customer_id: helpers.params[:customer_id]
        )
      end

      def test_connection_url
        helpers.test_connection_admin_settings_modules_payments_merchant_account_path(
          customer_id: helpers.params[:customer_id],
          id: account.id
        )
      end

      # ISO currency options for the select. Returns array of [label, value].
      def currency_options
        currencies = gateway&.supported_currencies || %w[cny]
        currencies.map { |c| [c.upcase, c.downcase] }
      end

      def credential_fields
        gateway&.credential_fields || []
      end

      def title
        gateway&.display_name || t("settings_modules.payments.provider_unavailable")
      end

      def merchant_id_value
        placeholder = "unset-#{account.provider}-#{account.mode}-#{account.customer_id}"
        account.merchant_id == placeholder ? nil : account.merchant_id
      end

      def credentials_present?
        gateway.present? && merchant_id_value.present? &&
          credential_fields.all? { |field| account.credential(field[:name]).present? }
      end

      private

      def edit_url_for(row)
        helpers.edit_admin_settings_modules_payments_merchant_account_path(
          customer_id: helpers.params[:customer_id],
          id: row.id
        )
      end
    end
  end
end
