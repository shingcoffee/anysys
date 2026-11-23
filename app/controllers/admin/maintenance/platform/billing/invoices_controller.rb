# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        class InvoicesController < BaseController
          before_action :set_invoice, only: %i[show mark_paid void retry]

          def index
            relation = filter_billing_invoices(::Billing::Invoice.unscoped_by_tenant.includes(:subscription, :customer),
                                               platform: true)
            @invoices = paginate_billing(recent_billing(relation))
            assign_invoice_history_collections(platform: true)
          end

          def show
            assign_invoice_collection(platform: true)
            # Authentication belongs on the purchasing tenant's invoice detail.
            @payment_action = nil
          end

          def mark_paid
            @settlement = params.fetch(:settlement, ActionController::Parameters.new).permit(:reference, :note).to_h
            result = ::Billing::Activities::MarkInvoicePaid.call(
              invoice: @invoice, source: :manual, actor: current_user,
              reference: @settlement["reference"], note: @settlement["note"]
            )
            case result.status
            when :paid
              redirect_invoice("invoice_marked_paid", number: @invoice.number)
            when :unchanged
              redirect_invoice("invoice_unchanged")
            when :review_required
              redirect_invoice("invoice_settlement_review", alert: true)
            else
              @invoice.reload
              assign_invoice_collection(platform: true)
              render_billing_failure(result, :show)
            end
          end

          def void
            result = ::Billing::Activities::VoidInvoice.call(invoice: @invoice)
            case result.status
            when :voided
              redirect_invoice("invoice_voided", number: @invoice.number)
            when :unchanged
              redirect_invoice("invoice_unchanged")
            else
              @invoice.reload
              assign_invoice_collection(platform: true)
              render_billing_failure(result, :show)
            end
          end

          def retry
            @submitted_collection = params.fetch(:collection, ActionController::Parameters.new).permit(:mode, :note).to_h.symbolize_keys
            if @submitted_collection.key?(:mode)
              authorization = ::Billing::Activities::AuthorizeInvoiceCollection.call(
                invoice: @invoice, actor: current_user, mode: @submitted_collection[:mode], note: @submitted_collection[:note]
              )
              unless %i[authorized saved updated unchanged].include?(authorization.status)
                @invoice.reload
                assign_invoice_collection(platform: true)
                return render_billing_failure(authorization, :show)
              end
            end
            result = ::Billing::Activities::CollectInvoice.call(invoice: @invoice, trigger: :recovery)
            if %i[succeeded pending requires_action pending_manual retry_scheduled].include?(result.status)
              redirect_to admin_maintenance_platform_billing_invoice_path(current_customer_id, @invoice), status: :see_other,
                          notice: t("admin_settings.flash.billing.collection.#{result.status}")
            else
              @invoice.reload
              assign_invoice_collection(platform: true)
              assign_billing_result(result)
              flash.now[:alert] = t("admin_settings.flash.billing.collection.#{result.status}",
                                    default: billing_failure_message(result))
              render :show, status: billing_failure_status(result)
            end
          end

          private

          def redirect_invoice(key, alert: false, **values)
            message = t("maint_platform.flash.billing.#{key}", **values)
            redirect_to admin_maintenance_platform_billing_invoice_path(current_customer_id, @invoice),
                        status: :see_other, **{ alert ? :alert : :notice => message }
          end

          def set_invoice
            @invoice = ::Billing::Invoice.unscoped_by_tenant.find(params[:id])
          end
        end
      end
    end
  end
end
