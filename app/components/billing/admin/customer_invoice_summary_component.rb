# frozen_string_literal: true

module Billing
  module Admin
    # At-a-glance billing figures above the tenant invoice history (Area b):
    # outstanding balance per currency and the latest settled payment.
    # +summary+ comes from PresentationFacts.invoice_summary.
    class CustomerInvoiceSummaryComponent < ApplicationComponent
      include Presentation

      attr_reader :summary, :customer_id

      def initialize(summary:, customer_id:)
        @summary = summary || {}
        @customer_id = customer_id.to_s
      end

      def outstanding = Array(fact(summary, :outstanding))
      def unpaid_count = fact(summary, :unpaid_count).to_i
      def last_paid = fact(summary, :last_paid)

      def outstanding? = unpaid_count.positive?

      def unpaid_path
        helpers.admin_settings_billing_invoices_path(customer_id, status: "open")
      end

      def date(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end
    end
  end
end
