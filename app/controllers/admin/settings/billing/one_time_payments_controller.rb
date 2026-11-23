# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      # One-time checkout for a single invoice.
      #
      # Placed under /:cid/admin/settings/billing/invoices/:invoice_id/one_time_payment
      # (admin URL area). Authorization is enforced globally by RouteAuthorization.
      #
      # TENANT SCOPING: set_invoice uses for_current_customer so a cross-tenant
      # ID yields 404 rather than leaking another tenant's invoice — including
      # when a platform owner is on another tenant's URL.
      class OneTimePaymentsController < BaseController
        before_action :set_invoice
        before_action :set_private_headers

        # GET — read-only. Query-string hints never start or confirm a payment.
        def show
          if @invoice.paid?
            return redirect_to admin_settings_billing_invoice_path(current_customer_id, @invoice),
                               status: :see_other,
                               notice: t("admin_settings.flash.billing.collection.succeeded")
          end

          @collection = billing_invoice_collection(@invoice)
          unless @collection[:can_pay_one_time]
            return redirect_to admin_settings_billing_invoice_path(current_customer_id, @invoice),
                               status: :see_other,
                               alert: billing_failure_message(::Billing::Result.new(status: :blocked, reason: @collection[:reason]))
          end

          @providers = billing_one_time_provider_options(@invoice.currency)
          @payment_action = ::Billing::OneTimePaymentAction.for(invoice: @invoice)
          render :show
        end

        def create
          result = ::Billing::Activities::StartOneTimePayment.call(
            invoice: @invoice,
            provider: one_time_payment_params[:provider],
            openid: one_time_payment_params[:openid],
            request: request
          )
          assign_billing_result(result)
          case result.status
          when :succeeded
            respond_to do |format|
              format.html do
                redirect_to admin_settings_billing_invoice_path(current_customer_id, @invoice),
                            status: :see_other,
                            notice: t("admin_settings.flash.billing.collection.succeeded")
              end
              format.json do
                render json: { invoice_id: @invoice.id, status: "succeeded",
                               invoice_url: admin_settings_billing_invoice_url(current_customer_id, @invoice) },
                       status: :ok
              end
            end
          when :action_required
            respond_to do |format|
              format.html do
                redirect_to admin_settings_billing_invoice_one_time_payment_path(current_customer_id, @invoice),
                            status: :see_other
              end
              format.json do
                render json: { invoice_id: @invoice.id, status: "action_required", action: result.action,
                               checkout_url: admin_settings_billing_invoice_one_time_payment_url(current_customer_id, @invoice) },
                       status: :ok
              end
            end
          when :pending
            respond_to do |format|
              format.html do
                redirect_to admin_settings_billing_invoice_one_time_payment_path(current_customer_id, @invoice),
                            status: :see_other,
                            notice: t("admin_settings.flash.billing.collection.pending")
              end
              format.json do
                render json: { invoice_id: @invoice.id, status: "pending",
                               checkout_url: admin_settings_billing_invoice_one_time_payment_url(current_customer_id, @invoice) },
                       status: :accepted
              end
            end
          else
            assign_one_time_failure(result)
            respond_to do |format|
              format.html do
                flash.now[:alert] = @one_time_error
                render :show, status: billing_failure_status(result)
              end
              format.json do
                render json: { status: result.status, reason: result.reason, error: @one_time_error },
                       status: billing_failure_status(result)
              end
            end
          end
        end

        # GET JSON poll for QR / PayPal. Server-verified; browser hints unused.
        def status
          result = ::Billing::Activities::ConfirmOneTimePayment.call(
            invoice: @invoice,
            out_trade_no: params[:out_trade_no]
          )
          return head :not_found if result.status == :invalid && result.reason == :payment_not_found

          payment_status = result.record&.payment&.status || (@invoice.reload.paid? ? "succeeded" : "pending")
          render json: { status: payment_status, invoice_status: @invoice.reload.status }
        end

        # POST — server-verified confirmation. Browser payment hints are ignored.
        def confirm
          result = ::Billing::Activities::ConfirmOneTimePayment.call(invoice: @invoice)
          assign_billing_result(result)
          case result.status
          when :succeeded
            respond_to do |format|
              format.html do
                redirect_to admin_settings_billing_invoice_path(current_customer_id, @invoice),
                            status: :see_other,
                            notice: t("admin_settings.flash.billing.collection.succeeded")
              end
              format.json do
                render json: { invoice_id: @invoice.id, status: "succeeded",
                               invoice_url: admin_settings_billing_invoice_url(current_customer_id, @invoice) },
                       status: :ok
              end
            end
          when :pending
            respond_to do |format|
              format.html do
                redirect_to admin_settings_billing_invoice_one_time_payment_path(current_customer_id, @invoice),
                            status: :see_other,
                            notice: t("admin_settings.flash.billing.collection.pending")
              end
              format.json do
                render json: { invoice_id: @invoice.id, status: "pending" }, status: :accepted
              end
            end
          else
            assign_one_time_failure(result)
            respond_to do |format|
              format.html do
                flash.now[:alert] = @one_time_error
                render :show, status: billing_failure_status(result)
              end
              format.json do
                render json: { status: result.status, reason: result.reason, error: @one_time_error },
                       status: billing_failure_status(result)
              end
            end
          end
        end

        private

        def set_invoice
          @invoice = ::Billing::Invoice.for_current_customer.find(params[:invoice_id])
        end

        def set_private_headers
          response.headers["Cache-Control"] = "no-store, private"
          response.headers["Referrer-Policy"] = "no-referrer"
        end

        def one_time_payment_params
          nested = params[:one_time_payment]
          if nested.is_a?(ActionController::Parameters)
            nested.permit(:provider, :openid)
          elsif nested.is_a?(Hash)
            ActionController::Parameters.new(nested).permit(:provider, :openid)
          else
            params.permit(:provider, :openid)
          end
        end

        def assign_one_time_failure(result)
          @invoice.reload
          @collection = billing_invoice_collection(@invoice)
          @providers = billing_one_time_provider_options(@invoice.currency)
          @payment_action = ::Billing::OneTimePaymentAction.for(invoice: @invoice)
          @one_time_error = billing_failure_message(result)
        end
      end
    end
  end
end
