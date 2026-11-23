# frozen_string_literal: true

module Billing
  module Admin
    # Modal picker for a one-time invoice payment from the subscription surface.
    class OneTimePaymentDialogComponent < ApplicationComponent
      include Presentation
      KIND_KEYS = %w[unpaid_invoice draft_initial draft_proration renewal].freeze

      def initialize(one_time_payment:, customer_id:, post_url:, open: false, error_message: nil)
        @one_time_payment = one_time_payment
        @customer_id = customer_id.to_s
        @post_url = post_url
        @open = open
        @error_message = error_message
      end

      attr_reader :one_time_payment, :customer_id, :post_url, :open, :error_message

      def dialog_id = "one-time-payment-dialog"

      def kind = fact(one_time_payment, :kind).to_s

      def kind_label
        I18n.t("settings_billing.one_time_payment.kinds.#{kind}") if KIND_KEYS.include?(kind)
      end

      def currency = fact(one_time_payment, :currency).to_s

      def amount_cents = fact(one_time_payment, :amount_cents)

      def formatted_amount = billing_amount(amount_cents, currency)

      def providers = Array(fact(one_time_payment, :providers))

      def invoice_id = fact(one_time_payment, :invoice_id)

      def invoice_number
        fact(one_time_payment, :invoice_number).presence || I18n.t("comp_billing.invoice_table.draft")
      end

      def period_start = fact(one_time_payment, :period_start)

      def period_end = fact(one_time_payment, :period_end)

      def due_at = fact(one_time_payment, :due_at)

      def date_label(value)
        return unless value.present?

        I18n.l(value.respond_to?(:to_date) ? value.to_date : value, format: :long)
      end
    end
  end
end
