# frozen_string_literal: true

module Billing
  module Admin
    # Provider picker for one-time invoice collection. Posts the selected
    # provider (and optional invoice id) without creating a recurring mandate.
    class OneTimeProviderTilesComponent < ApplicationComponent
      include Presentation

      def initialize(providers:, currency:, post_url:, scope: :one_time_payment, invoice_id: nil, selected_key: nil, columns: 3)
        @providers = Array(providers)
        @currency = currency
        @post_url = post_url
        @scope = scope
        @invoice_id = invoice_id
        @selected_key = selected_key
        @columns = columns
      end

      attr_reader :providers, :currency, :post_url, :scope, :invoice_id, :selected_key, :columns

      def enabled_providers
        providers.select { |opt| fact(opt, :enabled) != false }
      end

      def grid_class
        columns.to_i == 2 ? "sm:grid-cols-2" : "sm:grid-cols-2 xl:grid-cols-3"
      end

      def selected?(key)
        selected_key.present? && key.to_s == selected_key.to_s
      end

      def humanized_provider(key)
        descriptor = providers.find { |option| fact(option, :key).to_s == key.to_s }
        fallback = I18n.t("settings_billing.payment_methods.providers.#{key}", default: key.to_s)
        I18n.t(fact(descriptor, :label_key).presence || "settings_billing.payment_methods.providers.#{key}", default: fallback)
      end

      def provider_tile_class(key)
        PaymentMethodComponent::PROVIDER_TILE_CLASSES.fetch(key.to_s, "bg-surface-active text-text-secondary")
      end

      def disabled_reason(option)
        I18n.t(fact(option, :reason_key).presence || "settings_billing.payment_methods.currency_incompatible", currency: currency)
      end
    end
  end
end
