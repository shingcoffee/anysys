# frozen_string_literal: true

module Payments
  module Admin
    # Renders a table of reconciliation bills downloaded from payment
    # providers. Used by the admin reconciliations index page.
    class ReconciliationTableComponent < ApplicationComponent
      include Payments::Admin::CurrencyFormatting

      def initialize(bills:)
        @bills = bills
      end

      attr_reader :bills

      def status_variant(status)
        case status
        when "reconciled"  then :success
        when "parsed"      then :info
        when "discrepant"  then :warning
        when "failed"      then :danger
        else                    :default
        end
      end

      def status_label(status)
        I18n.t("comp_payments.reconciliation.statuses.#{status}")
      end

      def bill_type_label(bill_type)
        I18n.t("comp_payments.reconciliation.bill_types.#{bill_type}")
      end

      def provider_label(provider)
        Payments::Gateways.for(provider).display_name
      rescue ArgumentError
        provider.to_s
      end

      def bill_date_label(bill_date)
        return I18n.t("common.labels.em_dash") if bill_date.blank?

        I18n.l(bill_date.to_date, format: :long)
      end
    end
  end
end
