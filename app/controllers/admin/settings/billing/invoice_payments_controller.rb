# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      class InvoicePaymentsController < BaseController
        def create
          @invoice = ::Billing::Invoice.for_current_customer.find(params[:invoice_id])
          result = ::Billing::Activities::CollectInvoice.call(invoice: @invoice, trigger: :recovery)
          assign_billing_result(result)
          if %i[succeeded pending requires_action pending_manual retry_scheduled].include?(result.status)
            respond_to do |format|
              format.html do
                redirect_to admin_settings_billing_invoice_path(current_customer_id, @invoice), status: :see_other,
                            notice: t("admin_settings.flash.billing.collection.#{result.status}")
              end
              format.json do
                render json: { invoice_id: @invoice.id, status: result.status,
                               invoice_url: admin_settings_billing_invoice_url(current_customer_id, @invoice) },
                       status: %i[pending requires_action].include?(result.status) ? :accepted : :ok
              end
            end
          else
            respond_to do |format|
              format.html do
                @invoice.reload
                assign_invoice_collection
                @payment_action = ::Billing::InvoicePaymentAction.for(invoice: @invoice)
                response.headers["Cache-Control"] = "no-store, private"
                response.headers["Referrer-Policy"] = "no-referrer"
                flash.now[:alert] = t("admin_settings.flash.billing.collection.#{result.status}",
                                      default: billing_failure_message(result))
                render "admin/settings/billing/invoices/show", status: billing_failure_status(result)
              end
              format.json do
                render json: { status: result.status, reason: result.reason, error: billing_failure_message(result) },
                       status: billing_failure_status(result)
              end
            end
          end
        end
      end
    end
  end
end
