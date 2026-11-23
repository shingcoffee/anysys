# frozen_string_literal: true

module Payments
  module Admin
    # A single tile in the Gateway Gallery. Renders the gateway display name,
    # capability/flow chips, StatusBadge, mode badge, an enable/disable toggle
    # wired to the `payments--gateway-toggle` Stimulus controller, and a
    # "Configure" link to the edit path.
    #
    #   gateway — a Payments::Gateways::Base subclass (class object, not instance)
    #   account — a Payments::MerchantAccount row or nil (not yet provisioned)
    class GatewayCardComponent < ApplicationComponent
      # Flow / capability keys the card can render chips for. Display labels are
      # resolved at render time via I18n (see #flow_labels / #capability_labels)
      # so they bind to the request locale rather than class-load time.
      FLOW_KEYS       = %i[qr h5 jsapi card].freeze
      CAPABILITY_KEYS = %i[one_time recurring tokenized_cards refunds reconciliation webhooks].freeze

      attr_reader :gateway, :account, :default_provider

      def initialize(gateway:, account:, default_provider: nil)
        @gateway = gateway
        @account = account
        @default_provider = default_provider.to_s.presence
      end

      def default?
        default_provider.present? && default_provider == gateway.key.to_s
      end

      # Eligible to be set as default: enabled + configured (and not already it).
      def default_settable?
        account&.configured? == true && !default?
      end

      def set_default_url
        helpers.admin_settings_modules_payments_default_gateway_path(helpers.params[:customer_id])
      end

      # Derive display state from the account record.
      def gateway_state
        return :needs_setup if account.nil?
        return :active      if account.enabled?

        :disabled
      end

      def toggle_enabled?
        account&.enabled? == true
      end

      # Chips shown under the name: flows + notable capabilities
      def flow_labels
        gateway.supported_flows.filter_map do |f|
          I18n.t("comp_payments.gateway_card.flows.#{f}") if FLOW_KEYS.include?(f)
        end
      end

      def capability_labels
        caps = gateway.respond_to?(:capabilities) ? gateway.capabilities : %i[one_time refunds webhooks]
        caps.filter_map do |c|
          I18n.t("comp_payments.gateway_card.capabilities.#{c}") if CAPABILITY_KEYS.include?(c)
        end
      end

      def chip_labels
        (flow_labels + capability_labels).uniq
      end

      def mode_label
        account&.mode && I18n.t("settings_modules.payments.environments.#{account.mode}")
      end

      def mode_variant
        account&.mode == "production" ? :success : :warning
      end

      # The Configure link points at the `edit` action (GET /:id/edit), which is
      # the per-gateway config form. Falls back to the index/gallery when no
      # persisted account row exists yet.
      def configure_url
        if account&.persisted?
          helpers.edit_admin_settings_modules_payments_merchant_account_path(
            customer_id: helpers.params[:customer_id],
            id: account.id
          )
        else
          helpers.admin_settings_modules_payments_merchant_accounts_path(
            customer_id: helpers.params[:customer_id]
          )
        end
      end

      # The toggle PATCHes to the `update` action (the base member path without
      # an action prefix). This is distinct from the Configure edit link above.
      def toggle_url
        return nil unless account&.persisted?

        helpers.admin_settings_modules_payments_merchant_account_path(
          customer_id: helpers.params[:customer_id],
          id: account.id
        )
      end

      # Toggle is disabled (pointer-events-none) when needs_setup — admin must
      # configure credentials first.
      def toggle_interactive?
        gateway_state != :needs_setup
      end

      def card_classes
        "min-w-0 rounded-xl border border-border-subtle bg-surface p-4 sm:p-5 flex flex-col gap-5"
      end

      def credentials_present?
        return false unless account && account.merchant_id.present?
        return false if account.merchant_id == "unset-#{account.provider}-#{account.mode}-#{account.customer_id}"

        gateway.credential_fields.all? { |field| account.credential(field[:name]).present? }
      end
    end
  end
end
