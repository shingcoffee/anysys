# frozen_string_literal: true

module Payments
  module Member
    # Member self-service: lists saved payment methods (tokenized cards) and
    # provides an "Add card" panel backed by the Stripe SetupIntent flow.
    #
    # All URLs are passed as constructor props — no route helpers are called
    # inside this component, so specs can pass plain strings.
    #
    # Props:
    #   payment_methods:  Array<Payments::PaymentMethod>
    #   setup_intent_url: String — POST endpoint that returns SetupIntent client_secret
    #   create_url:       String — POST endpoint that confirms the vault row
    #   destroy_url_proc: Proc/Method|nil — called with (payment_method) → String URL
    #   publishable_key:  String|nil — Stripe publishable key; nil = not configured
    class PaymentMethodsComponent < ApplicationComponent
      include ::Member::UsesSiteChrome
      attr_reader :payment_methods, :setup_intent_url, :create_url,
                  :destroy_url_proc, :publishable_key

      def initialize(payment_methods:, setup_intent_url:, create_url:,
                     destroy_url_proc: nil, publishable_key: nil)
        @payment_methods  = payment_methods
        @setup_intent_url = setup_intent_url
        @create_url       = create_url
        @destroy_url_proc = destroy_url_proc
        @publishable_key  = publishable_key
      end

      def any_cards?
        payment_methods.any?
      end

      def stripe_configured?
        publishable_key.present?
      end

      # Returns the destroy URL for a given payment method by calling destroy_url_proc,
      # or nil when no proc is supplied.
      def destroy_url_for(pm)
        destroy_url_proc&.call(pm)
      end

      def expiry_label(pm)
        format("%02d/%d", pm.exp_month.to_i, pm.exp_year.to_i)
      end
    end
  end
end
