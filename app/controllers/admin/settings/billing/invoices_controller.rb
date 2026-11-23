# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      # Read-only view of the current customer's billing invoices.
      #
      # index    — paginated list of all invoices for the current customer.
      # show     — detail view of a single invoice.
      # download — renderable download/print view of a single invoice.
      #
      # TENANT SCOPING: every query is scoped to the current customer via
      # for_current_customer (TenantScoped). The set_invoice before_action
      # re-applies the same scope so a cross-tenant ID yields 404 rather
      # than leaking another tenant's invoice.
      class InvoicesController < BaseController
        before_action :set_invoice, only: %i[show download]

        # GET /:cid/admin/settings/billing/invoices
        def index
          relation = filter_billing_invoices(::Billing::Invoice.for_current_customer.includes(:subscription), search: false)
          @invoices = paginate_billing(recent_billing(relation))
          assign_invoice_history_collections
          @invoice_summary = billing_invoice_summary(::Billing::Invoice.for_current_customer)
        end

        # GET /:cid/admin/settings/billing/invoices/:id
        def show
          assign_invoice_collection
          @payment_action = ::Billing::InvoicePaymentAction.for(invoice: @invoice)
          response.headers["Cache-Control"] = "no-store, private"
          response.headers["Referrer-Policy"] = "no-referrer"
        end

        # GET /:cid/admin/settings/billing/invoices/:id/download
        def download
          billing_filters(statuses: ::Billing::Invoice::STATUSES)
        end

        private

        # Scopes lookup to current_customer_id so cross-tenant IDs 404 naturally.
        def set_invoice
          @invoice = ::Billing::Invoice
                       .for_current_customer
                       .find(params[:id])
        end
      end
    end
  end
end
