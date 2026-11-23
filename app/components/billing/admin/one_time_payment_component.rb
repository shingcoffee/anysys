# frozen_string_literal: true

require "rqrcode"

module Billing
  module Admin
    # Dedicated one-time invoice checkout: provider selection plus the active
    # Stripe / PayPal / QR / H5 / JSAPI completion mount.
    class OneTimePaymentComponent < ApplicationComponent
      include Presentation

      def initialize(invoice:, customer_id:, providers:, payment_action: nil, post_url: nil, status_url: nil,
                     confirm_url: nil, result_url: nil, back_url: nil, error_message: nil)
        @invoice = invoice
        @customer_id = customer_id.to_s
        @providers = Array(providers)
        @payment_action = payment_action
        @post_url = post_url
        @status_url = status_url
        @confirm_url = confirm_url
        @result_url = result_url
        @back_url = back_url
        @error_message = error_message
      end

      attr_reader :invoice, :customer_id, :providers, :payment_action, :post_url, :status_url, :confirm_url,
                  :result_url, :back_url, :error_message

      def action_kind
        fact(payment_action, :kind)&.to_sym
      end

      def provider_key
        fact(payment_action, :provider).presence || action_kind.to_s
      end

      def provider_label
        descriptor = providers.find { |option| fact(option, :key).to_s == provider_key.to_s }
        fallback = I18n.t("settings_billing.payment_methods.providers.#{provider_key}", default: provider_key.to_s)
        I18n.t(fact(descriptor, :label_key).presence || "settings_billing.payment_methods.providers.#{provider_key}", default: fallback)
      end

      def formatted_total
        billing_amount(invoice.total_cents, invoice.currency)
      end

      def status_variant
        InvoiceDetailComponent::STATUS_BADGE_MAP.fetch(invoice.status.to_s, :default)
      end

      def status_label
        key = invoice.status.to_s
        Billing::Invoice::STATUSES.include?(key) ? I18n.t("comp_billing.invoice_table.statuses.#{key}") : key
      end

      def date_label(value)
        value.present? ? I18n.l(value.respond_to?(:to_date) ? value.to_date : value, format: :long) : I18n.t("common.labels.em_dash")
      end

      def invoice_param
        invoice.respond_to?(:to_param) ? invoice.to_param : invoice.id
      end

      def resolved_post_url
        post_url.presence || helpers.admin_settings_billing_invoice_one_time_payment_path(customer_id, invoice)
      end

      def resolved_status_url
        status_url.presence || helpers.status_admin_settings_billing_invoice_one_time_payment_path(customer_id, invoice)
      end

      def resolved_confirm_url
        confirm_url.presence || helpers.confirm_admin_settings_billing_invoice_one_time_payment_path(customer_id, invoice)
      end

      def resolved_result_url
        result_url.presence || invoice_show_path
      end

      def resolved_back_url
        back_url.presence || invoice_show_path
      end

      def stripe_data
        {
          "controller" => "payments--stripe-card",
          "payments--stripe-card-publishable-key-value" => fact(payment_action, :publishable_key),
          "payments--stripe-card-client-secret-value" => fact(payment_action, :client_secret),
          "payments--stripe-card-result-url-value" => resolved_result_url,
          "payments--stripe-card-unavailable-text-value" => I18n.t("comp_payments.shared.stripe_unavailable"),
          "payments--stripe-card-unexpected-error-value" => I18n.t("comp_payments.stripe.unexpected_error"),
          "payments--stripe-card-setup-intent-failed-value" => I18n.t("comp_payments.stripe.setup_intent_failed"),
          "payments--stripe-card-missing-client-secret-value" => I18n.t("comp_payments.stripe.missing_client_secret"),
          "payments--stripe-card-missing-payment-method-value" => I18n.t("comp_payments.stripe.missing_payment_method"),
          "payments--stripe-card-server-error-value" => I18n.t("comp_payments.stripe.server_error"),
          "payments--stripe-card-processing-text-value" => I18n.t("comp_payments.stripe.processing")
        }
      end

      def paypal_data
        {
          "controller" => "payments--paypal-buttons",
          "payments--paypal-buttons-client-id-value" => fact(payment_action, :client_id),
          "payments--paypal-buttons-paypal-order-id-value" => fact(payment_action, :paypal_order_id),
          "payments--paypal-buttons-currency-value" => invoice.currency.to_s,
          "payments--paypal-buttons-status-url-value" => resolved_status_url,
          "payments--paypal-buttons-result-url-value" => resolved_result_url,
          "payments--paypal-buttons-sdk-error-value" => I18n.t("comp_payments.paypal.sdk_error"),
          "payments--paypal-buttons-cancelled-text-value" => I18n.t("comp_payments.paypal.cancelled"),
          "payments--paypal-buttons-error-text-value" => I18n.t("comp_payments.paypal.error")
        }
      end

      def qr_data
        {
          "controller" => "payments--qr-poll",
          "payments--qr-poll-status-url-value" => resolved_status_url,
          "payments--qr-poll-result-url-value" => resolved_result_url,
          "payments--qr-poll-status-prefix-value" => I18n.t("comp_payments.result.status_prefix"),
          "payments--qr-poll-status-labels-value" => status_labels_json
        }
      end

      def h5_url
        fact(payment_action, :url).presence || fact(payment_action, :redirect_url).presence || fact(payment_action, :h5_url)
      end

      def jsapi_data
        {
          "controller" => "payments--jsapi-invoker",
          "payments--jsapi-invoker-provider-value" => provider_key.to_s,
          "payments--jsapi-invoker-params-value" => jsapi_params_json,
          "payments--jsapi-invoker-result-url-value" => resolved_result_url
        }
      end

      def qr_svg
        code = fact(payment_action, :code_url).presence || fact(payment_action, :qr_code)
        return "".html_safe if code.to_s.empty?

        RQRCode::QRCode.new(code.to_s, level: :m).as_svg(
          offset: 0,
          color: "000",
          shape_rendering: "crispEdges",
          module_size: 5,
          standalone: true,
          use_path: true
        ).html_safe
      end

      def status_labels_json
        %i[pending succeeded failed closed].index_with do |status|
          I18n.t("comp_payments.result.statuses.#{status}")
        end.to_json
      end

      private

      def jsapi_params_json
        params = fact(payment_action, :jsapi_params) || fact(payment_action, :params)
        params.is_a?(String) ? params : (params || {}).to_json
      end

      def invoice_show_path
        helpers.admin_settings_billing_invoice_path(customer_id, invoice)
      end
    end
  end
end
