# frozen_string_literal: true

module Billing
  module Admin
    class PaymentAuthorizationComponent < PaymentMethodComponent
      def initialize(available_providers:, customer_id:, provider_options: nil, currency: nil, authorization: nil, request_key: nil, payment_method: nil)
        super(payment_methods: [], available_providers: available_providers, customer_id: customer_id,
              provider_options: provider_options, currency: currency, authorization: authorization, request_key: request_key)
        @payment_method = payment_method
      end

      attr_reader :payment_method

      def enabled_provider_options
        provider_options.select { |option| fact(option, :enabled) != false }
      end

      def disabled_provider_options
        provider_options.select { |option| fact(option, :enabled) == false }
      end

      def authorization_kind
        kind = fact(authorization, :kind).to_s
        return if kind == "stripe_setup" && fact(authorization, :publishable_key).blank?

        kind.presence_in(%w[redirect provider_form stripe_setup])
      end

      def redirect_provider_key
        payment_method&.provider.presence || fact(authorization, :provider).presence || "alipay"
      end

      def confirmation_url
        fact(authorization, :confirmation_url).presence ||
          (payment_method && helpers.confirmation_admin_settings_billing_payment_method_path(customer_id, payment_method))
      end

      def stripe_data
        {
          controller: "payments--stripe-card", payments__stripe_card_publishable_key_value: fact(authorization, :publishable_key),
          payments__stripe_card_billing_setup_value: true,
          payments__stripe_card_setup_intent_url_value: setup_intent_path,
          payments__stripe_card_setup_client_secret_value: fact(authorization, :client_secret),
          payments__stripe_card_confirmation_url_value: confirmation_url,
          payments__stripe_card_request_key_value: request_key,
          payments__stripe_card_result_url_value: fact(authorization, :result_url).presence || helpers.admin_settings_billing_payment_methods_url(customer_id, authorization_request_key: request_key),
          payments__stripe_card_unavailable_text_value: I18n.t("comp_payments.shared.stripe_unavailable"),
          payments__stripe_card_unexpected_error_value: I18n.t("comp_payments.stripe.unexpected_error"),
          payments__stripe_card_setup_intent_failed_value: I18n.t("comp_payments.stripe.setup_intent_failed"),
          payments__stripe_card_missing_client_secret_value: I18n.t("comp_payments.stripe.missing_client_secret"),
          payments__stripe_card_missing_payment_method_value: I18n.t("comp_payments.stripe.missing_payment_method"),
          payments__stripe_card_missing_confirmation_url_value: I18n.t("comp_billing.stripe.missing_confirmation_url"),
          payments__stripe_card_server_error_value: I18n.t("comp_payments.stripe.server_error"),
          payments__stripe_card_processing_text_value: I18n.t("comp_payments.stripe.processing")
        }.transform_keys { |key| key.to_s.gsub("__", "--") }
      end
    end
  end
end
