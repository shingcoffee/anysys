# frozen_string_literal: true

module Payments
  module Admin
    # Renders a table of recent payment transactions. Succeeded rows link to
    # the refund review page; other rows link to the same show surface.
    class TransactionTableComponent < ApplicationComponent
      include CurrencyFormatting

      def initialize(payments:)
        @payments = payments
      end

      attr_reader :payments

      # Amount in the payment's own currency (via its order) — never a hard-coded
      # symbol; multi-currency gateways (Stripe/PayPal) make non-CNY rows common.
      def formatted_amount(payment)
        format_money(payment.amount, payment.payment_order&.currency)
      end

      def status_variant(status)
        case status
        when "succeeded" then :success
        when "failed"    then :danger
        when "pending"   then :warning
        else                  :default
        end
      end

      def status_label(status)
        key = status.to_s
        if Payments::Payment::STATUSES.include?(key)
          I18n.t("comp_payments.transaction_table.statuses.#{key}")
        else
          key
        end
      end

      def provider_label(provider)
        Payments::Gateways.for(provider).display_name
      rescue ArgumentError
        provider.to_s
      end

      def transaction_path(payment)
        helpers.admin_modules_payments_transaction_path(
          customer_id: helpers.params[:customer_id],
          id: payment.id
        )
      end

      # An extra badge flagging a dispute on this payment: a lost dispute
      # (chargeback) outranks an open/under-review one. Returns nil when there is
      # no dispute worth flagging (none, or all won/closed).
      def dispute_flag(payment)
        disputes = payment.payment_disputes.to_a
        return nil if disputes.empty?

        if disputes.any? { |d| d.status == "lost" }
          { variant: :danger,  key: "chargeback" }
        elsif disputes.any? { |d| d.status.in?(%w[open under_review]) }
          { variant: :warning, key: "disputed" }
        end
      end
    end
  end
end
