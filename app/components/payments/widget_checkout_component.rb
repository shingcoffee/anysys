# frozen_string_literal: true

module Payments
  # Vendor-agnostic checkout component for in-page payment widgets (e.g.
  # Stripe Card, PayPal Smart Buttons). The rendering is driven entirely by
  # the descriptor hash returned by `gateway.checkout_widget` so no new
  # component is needed when a gateway is added.
  #
  # Props:
  #   order:           Payments::Order
  #   payment:         Payments::Payment — must have prepay_payload with string
  #                    keys matching the gateway's `value_keys`
  #   gateway:         Gateway CLASS responding to `.checkout_widget`
  #   result_url:      String — redirect target after payment is confirmed
  #   status_url:      String — JSON status endpoint polled / used post-approval
  # Save-card consent is submitted by CheckoutComponent before charge.
  #
  # checkout_widget descriptor shape:
  #   {
  #     controller:         "payments--stripe-card",      # Stimulus controller id
  #     value_keys:         %i[publishable_key client_secret],
  #     renders_pay_button: true,   # component renders the Pay button
  #     secured_by:         "Stripe"
  #   }
  class WidgetCheckoutComponent < ApplicationComponent
    attr_reader :order, :payment, :gateway, :result_url, :status_url

    def initialize(order:, payment:, gateway:, result_url:, status_url:)
      @order          = order
      @payment        = payment
      @gateway        = gateway
      @result_url     = result_url
      @status_url     = status_url
    end

    # The checkout_widget descriptor from the gateway class.
    def widget
      @widget ||= gateway.checkout_widget
    end

    # The Stimulus controller identifier (e.g. "payments--stripe-card").
    def controller_id
      widget[:controller]
    end

    # True when the gateway widget renders its own Pay button; the component
    # should then also render a Pay button (e.g. Stripe). False for gateways
    # that inject their own buttons (e.g. PayPal Smart Buttons).
    def renders_pay_button?
      !!widget[:renders_pay_button]
    end

    # Human-readable vendor name shown in the trust footer.
    def secured_by
      widget[:secured_by]
    end

    # Formatted order total in major currency units.
    # Zero-decimal currencies (e.g. JPY) are rendered as integers ("1000");
    # standard currencies are rendered with two decimal places ("49.99").
    def formatted_amount
      Payments::Money.new(order.amount, order.currency).decimal_string
    end

    # ISO currency code, uppercased (e.g. "USD").
    def currency_code
      order.currency.to_s.upcase
    end

    # Full data hash for the widget wrapper div, consumed by the tag helper.
    # Includes `controller:` plus every value attribute from widget_data.
    # String keys are used throughout so Rails does not transform `--` separators.
    def widget_container_data
      { "controller" => controller_id }.merge(widget_data)
    end

    # Data hash for the widget mount-point div (element target).
    def element_target_data
      { "#{controller_id}-target" => "element" }
    end

    # Data hash for the inline error paragraph (error target).
    def error_target_data
      { "#{controller_id}-target" => "error" }
    end

    # Data hash for the Pay button (action attribute).
    def pay_button_data
      { "action" => "click->#{controller_id}#submit" }
    end

    private

    # Hash of bare data-attribute names (without leading "data-") → values
    # for the widget wrapper. Always includes result-url and status-url, then
    # projects each of the gateway's value_keys from payment.prepay_payload
    # (string-keyed JSON). Used by widget_container_data.
    def widget_data
      base = {
        "#{controller_id}-result-url-value" => result_url,
        "#{controller_id}-status-url-value" => status_url,
        # Read only by payments--stripe-card today; harmless (unused) for
        # gateways whose controller doesn't declare an unavailableText value.
        "#{controller_id}-unavailable-text-value" => I18n.t("comp_payments.shared.stripe_unavailable")
      }
      widget[:value_keys].each do |key|
        attr_name = "#{controller_id}-#{key.to_s.tr('_', '-')}-value"
        base[attr_name] = payment.prepay_payload[key.to_s]
      end
      base.merge!(controller_i18n_data)
      base
    end

    def controller_i18n_data
      case controller_id
      when "payments--paypal-buttons"
        {
          "#{controller_id}-sdk-error-value"      => I18n.t("comp_payments.paypal.sdk_error"),
          "#{controller_id}-cancelled-text-value" => I18n.t("comp_payments.paypal.cancelled"),
          "#{controller_id}-error-text-value"     => I18n.t("comp_payments.paypal.error")
        }
      when "payments--stripe-card"
        {
          "#{controller_id}-unexpected-error-value"       => I18n.t("comp_payments.stripe.unexpected_error"),
          "#{controller_id}-setup-intent-failed-value"    => I18n.t("comp_payments.stripe.setup_intent_failed"),
          "#{controller_id}-missing-client-secret-value"  => I18n.t("comp_payments.stripe.missing_client_secret"),
          "#{controller_id}-missing-payment-method-value" => I18n.t("comp_payments.stripe.missing_payment_method"),
          "#{controller_id}-server-error-value"           => I18n.t("comp_payments.stripe.server_error"),
          "#{controller_id}-processing-text-value"        => I18n.t("comp_payments.stripe.processing")
        }
      else
        {}
      end
    end
  end
end
