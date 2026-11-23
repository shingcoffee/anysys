# frozen_string_literal: true

module Payments
  module Admin
    # Read-only table of card disputes / chargebacks for the admin dashboard.
    class DisputeTableComponent < ApplicationComponent
      include CurrencyFormatting

      REASON_KEYS = %w[
        bank_cannot_process
        check_returned
        credit_not_processed
        customer_initiated
        debit_not_authorized
        duplicate
        fraudulent
        general
        incorrect_account_details
        insufficient_funds
        product_not_received
        product_unacceptable
        subscription_canceled
        unrecognized
        MERCHANDISE_OR_SERVICE_NOT_RECEIVED
        MERCHANDISE_OR_SERVICE_NOT_AS_DESCRIBED
        UNAUTHORISED
        CREDIT_NOT_PROCESSED
        DUPLICATE_TRANSACTION
        INCORRECT_AMOUNT
        PAYMENT_BY_OTHER_MEANS
        CANCELED_RECURRING_BILLING
        PROBLEM_WITH_REMITTANCE
        OTHER
      ].freeze

      def initialize(disputes:)
        @disputes = disputes
      end

      attr_reader :disputes

      def status_variant(status)
        case status
        when "won"          then :success
        when "lost"         then :danger
        when "under_review" then :warning
        when "closed"       then :default
        else                     :warning # open
        end
      end

      # Localized status label; unknown values stay as the raw key.
      def status_label(status)
        key = status.to_s
        if Payments::Dispute::STATUSES.include?(key)
          I18n.t("comp_payments.dispute_table.statuses.#{key}")
        else
          key
        end
      end

      def provider_label(provider)
        Payments::Gateways.for(provider).display_name
      rescue ArgumentError
        provider.to_s
      end

      def reason_label(reason)
        key = reason.to_s
        return I18n.t("common.labels.em_dash") if key.blank?

        if REASON_KEYS.include?(key)
          I18n.t("comp_payments.dispute_table.reasons.#{key}")
        else
          key
        end
      end

      # Amount formatted in the disputed payment's own currency (via the order).
      def formatted_amount(dispute)
        format_money(dispute.amount, dispute.payment&.payment_order&.currency)
      end
    end
  end
end
