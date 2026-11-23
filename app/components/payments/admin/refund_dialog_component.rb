# frozen_string_literal: true

module Payments
  module Admin
    # Renders a refund form for a single payment, allowing an admin to pick
    # amount (capped at the original amount) and reason. Used by the admin
    # transaction show page.
    class RefundDialogComponent < ApplicationComponent
      include CurrencyFormatting

      def initialize(payment:)
        @payment = payment
      end

      attr_reader :payment

      def formatted_amount
        format_money(payment.amount, payment.payment_order.currency)
      end

      def status_label
        key = payment.status.to_s
        if Payments::Payment::STATUSES.include?(key)
          I18n.t("comp_payments.transaction_table.statuses.#{key}")
        else
          key
        end
      end

      def provider_label
        Payments::Gateways.for(payment.provider).display_name
      rescue ArgumentError
        payment.provider.to_s
      end
    end
  end
end
