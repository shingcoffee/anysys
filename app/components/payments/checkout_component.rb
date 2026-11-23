# frozen_string_literal: true

module Payments
  # Checkout landing page: renders one submit button per eligible gateway,
  # default first. Receives the gateway list — no registry/DB access here.
  class CheckoutComponent < ApplicationComponent
    def initialize(order:, gateways: [], default_provider: nil, errors: nil)
      @order  = order
      @errors = errors
      @default_provider = default_provider.to_s.presence
      @gateways = order_with_default_first(gateways)
    end

    attr_reader :order, :errors, :gateways, :default_provider

    def any_gateways?
      gateways.any?
    end

    def formatted_amount
      Payments::Money.new(order.amount, order.currency).decimal_string
    end

    # Consent must accompany the provider-selection POST, before its intent is
    # created. The supplied eligible gateway is the provider this form submits.
    def show_save_card?(gateway)
      return false unless gateway.key.to_s == "stripe" && gateway.capabilities.include?(:tokenized_cards)

      user = helpers.current_user
      user&.member? && order.customer_id.present? && user.customer_id == order.customer_id
    end

    private

    def order_with_default_first(list)
      return list if default_provider.blank?

      default, rest = list.partition { |gw| gw.key.to_s == default_provider }
      default + rest
    end
  end
end
