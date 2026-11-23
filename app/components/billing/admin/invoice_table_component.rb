# frozen_string_literal: true

module Billing
  module Admin
    # Renders a responsive table of billing invoices.
    # Works for the customer settings view (Area b), module area (Area a), and
    # the platform-wide view (Area d), controlled by the +context+ option.
    #
    # Constructor:
    #   invoices:    Array/relation of Billing::Invoice records
    #   customer_id: current customer_id for building route helpers
    #   context:     Symbol — :settings (default), :modules, or :platform
    #                :platform also enables the Customer column
    class InvoiceTableComponent < ApplicationComponent
      include Presentation
      STATUS_BADGE_MAP = {
        "draft"         => :default,
        "open"          => :warning,
        "paid"          => :success,
        "void"          => :default,
        "uncollectible" => :danger
      }.freeze

      CONTEXTS = %i[settings modules platform].freeze

      def initialize(invoices:, customer_id:, context: :settings, customer_settings: false,
                     filters: {}, pagination: nil, page_path: nil, history_url: nil, collection_by_invoice_id: {}, load_error: nil)
        @invoices    = invoices
        @customer_id = customer_id.to_s
        @context     = context.to_sym
        @customer_settings = customer_settings && @context == :settings
        @filters, @pagination, @page_path, @history_url = filters, pagination, page_path, history_url
        @collection_by_invoice_id, @load_error = collection_by_invoice_id || {}, load_error
      end

      attr_reader :invoices, :customer_id, :context, :customer_settings
      attr_reader :filters, :pagination, :page_path, :collection_by_invoice_id, :load_error

      def platform? = context == :platform

      def status_variant(status)
        STATUS_BADGE_MAP.fetch(status.to_s, :default)
      end

      def status_label(status)
        key = status.to_s
        if Billing::Invoice::STATUSES.include?(key)
          I18n.t("comp_billing.invoice_table.statuses.#{key}")
        else
          key
        end
      end

      def format_amount(amount_cents, currency)
        billing_amount(amount_cents, currency)
      end

      def invoice_path(invoice)
        case context
        when :platform then helpers.admin_maintenance_platform_billing_invoice_path(customer_id, invoice, **permitted_filters)
        else helpers.admin_settings_billing_invoice_path(customer_id, invoice, **permitted_filters)
        end
      end

      def download_path(invoice)
        helpers.download_admin_settings_billing_invoice_path(download_customer_id(invoice), invoice)
      end

      def download_customer_id(invoice)
        platform? ? invoice.customer_id : customer_id
      end
      private :download_customer_id

      def filter_keys = platform? && @history_url.nil? ? %i[q status tenant_id] : %i[q status]

      def history_path(**query)
        return query.empty? ? @history_url : "#{@history_url}?#{query.to_query}" if @history_url

        platform? ? helpers.admin_maintenance_platform_billing_invoices_path(customer_id, **query) : helpers.admin_settings_billing_invoices_path(customer_id, **query)
      end

      def empty_key = filtered? ? "comp_billing.history.no_matches" : "comp_billing.invoice_table.empty"

      def date_label(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def customer_name(invoice)
        invoice.customer.name if invoice.respond_to?(:customer) && invoice.customer.respond_to?(:name)
      end

      def collection_label(invoice)
        state = fact(collection_by_invoice_id[invoice.id] || collection_by_invoice_id[invoice.id.to_s], :state).presence || fact(invoice, :collection_state)
        state = { "paid" => "settled", "void" => "stopped", "draft" => "draft" }.fetch(invoice.status, state)
        I18n.t("comp_billing.collection.states.#{state.presence || 'unavailable'}")
      end

      def unpaid?(invoice) = invoice.status.to_s.in?(%w[open uncollectible])

      def can_pay_one_time?(invoice)
        customer_settings && unpaid?(invoice) &&
          fact(collection_by_invoice_id[invoice.id] || collection_by_invoice_id[invoice.id.to_s], :can_pay_one_time) == true
      end

      def one_time_payment_path(invoice)
        helpers.admin_settings_billing_invoice_one_time_payment_path(customer_id, invoice)
      end
    end
  end
end
