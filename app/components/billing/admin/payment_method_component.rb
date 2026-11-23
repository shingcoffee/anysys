# frozen_string_literal: true

module Billing
  module Admin
    # Renders the Payment Method tab for the customer billing settings area.
    #
    # Displays every stored method, with server-supplied charge readiness:
    #   - Provider display label, status badge, authorized date
    #   - A "Default" badge on the default method
    #   - A "Make Default" action on non-default methods
    #   - Local removal for active, pending and failed methods
    #
    # When no methods exist, renders an empty-state with one CTA form per
    # available provider (mandate flow — no raw card input).
    #
    # When no providers are configured by the platform, renders a help message.
    #
    # Constructor:
    #   payment_methods:      Array/Relation of all Billing::PaymentMethod rows
    #   available_providers:  Array of provider key strings (e.g. ["alipay","wechat_pay"])
    #   customer_id:          String/Integer — used for route helpers
    class PaymentMethodComponent < ApplicationComponent
      include Presentation
      STATUS_BADGE_MAP = {
        "pending" => :warning,
        "active"  => :success,
        "failed"  => :danger,
        "removed" => :default
      }.freeze
      PROVIDER_TILE_CLASSES = {
        "alipay"     => "bg-info-subtle text-info",
        "wechat_pay" => "bg-success-subtle text-success",
        "stripe"     => "bg-accent-subtle text-accent-text",
        "paypal"     => "bg-canvas-elevated text-text-primary"
      }.freeze

      def initialize(payment_methods:, available_providers:, customer_id:, customer_settings: false,
                     currency: nil, provider_options: nil, payment_method_readiness: {}, authorization: nil,
                     request_key: nil, form: nil, pagination: nil, page_path: nil)
        @payment_methods     = Array(payment_methods)
        @available_providers = Array(available_providers)
        @customer_id         = customer_id.to_s
        @customer_settings   = customer_settings
        @currency, @authorization, @form = currency, authorization, form
        @provider_options = provider_options || []
        @payment_method_readiness = payment_method_readiness || {}
        @request_key = request_key.presence || form_value(:request_key).presence || SecureRandom.uuid
        @pagination, @page_path = pagination, page_path
      end

      attr_reader :payment_methods, :available_providers, :customer_id, :customer_settings
      attr_reader :currency, :provider_options, :payment_method_readiness, :authorization, :request_key, :form
      attr_reader :pagination, :page_path

      def has_methods?
        payment_methods.any?
      end

      def has_providers?
        provider_options.any?
      end

      def status_variant(status)
        STATUS_BADGE_MAP.fetch(status.to_s, :default)
      end

      def status_label(status)
        key = status.to_s
        return key unless Billing::PaymentMethod::STATUSES.include?(key)

        I18n.t("comp_billing.payment_method.statuses.#{key}")
      end

      def humanized_provider(key)
        descriptor = provider_options.find { |option| fact(option, :key).to_s == key.to_s }
        fallback = I18n.t("settings_billing.payment_methods.providers.#{key}", default: key.to_s)
        I18n.t(fact(descriptor, :label_key).presence || "settings_billing.payment_methods.providers.#{key}", default: fallback)
      end

      def provider_tile_class(key)
        PROVIDER_TILE_CLASSES.fetch(key.to_s, "bg-surface-active text-text-secondary")
      end

      def formatted_authorized_at(payment_method)
        return I18n.t("common.labels.em_dash") unless payment_method.authorized_at

        I18n.l(payment_method.authorized_at, format: :short)
      end

      def destroy_path(payment_method)
        helpers.admin_settings_billing_payment_method_path(customer_id, payment_method)
      end

      def make_default_path(payment_method)
        helpers.make_default_admin_settings_billing_payment_method_path(customer_id, payment_method)
      end

      def create_path
        helpers.admin_settings_billing_payment_methods_path(customer_id)
      end

      def readiness(payment_method)
        payment_method_readiness[payment_method.id] || payment_method_readiness[payment_method.id.to_s] || {}
      end

      def ready?(payment_method)
        payment_method.status == "active" && fact(readiness(payment_method), :charge_ready) == true
      end

      def eligible_provider?(key)
        provider_options.any? { |option| fact(option, :key).to_s == key.to_s && fact(option, :enabled) != false }
      end

      def authorization_path(payment_method)
        helpers.authorization_admin_settings_billing_payment_method_path(customer_id, payment_method)
      end

      def setup_intent_path
        helpers.setup_intent_admin_settings_billing_payment_methods_path(customer_id)
      end
    end
  end
end
