# frozen_string_literal: true

module Billing
  module Admin
    # Customer settings presentation of the invoice history (Area b). Shares
    # routes, filters and collection facts with InvoiceTableComponent.
    class CustomerInvoiceTableComponent < InvoiceTableComponent
      QUICK_STATUSES = [nil, "open", "paid", "uncollectible", "void"].freeze

      def initialize(**options)
        super(**options, context: :settings, customer_settings: true)
      end

      def filter_keys = %i[status]

      def date_label(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def unpaid?(invoice) = invoice.status.to_s.in?(%w[open uncollectible])

      def show_collection_note?(invoice) = unpaid?(invoice)

      def view_button_class(invoice)
        if can_pay_one_time?(invoice)
          "btn btn-secondary btn-sm"
        elsif unpaid?(invoice)
          "btn btn-primary btn-sm"
        else
          "btn btn-ghost btn-sm"
        end
      end

      def period_label(invoice)
        start, finish = fact(invoice, :period_start), fact(invoice, :period_end)
        return unless start && finish

        I18n.t("comp_billing.period_range", start: I18n.l(start.to_date, format: :short), end: I18n.l(finish.to_date, format: :short))
      end

      def quick_filter_pills
        QUICK_STATUSES.map do |status|
          current = status.nil? ? permitted_filters[:status].blank? : permitted_filters[:status].to_s == status
          {
            status: status,
            label: status ? I18n.t("comp_billing.invoice_table.statuses.#{status}") : I18n.t("settings_billing.invoices.all_filter"),
            href: history_path(**(status ? { status: status } : {})),
            current: current
          }
        end
      end

      def quick_filter_class(current)
        base = "rounded-md px-3 py-1.5 text-body-sm font-medium transition-colors"
        current ? "#{base} bg-surface text-text-primary shadow-xs" : "#{base} text-text-secondary hover:text-text-primary"
      end
    end
  end
end
