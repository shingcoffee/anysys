# frozen_string_literal: true

module Admin
  module Settings
    module Billing
      # Starts a one-time payment from the subscription settings surface.
      #
      # POST /:cid/admin/settings/billing/subscription/one_time_payment
      # Authorization is enforced globally by RouteAuthorization. A supplied
      # invoice_id is looked up with for_current_customer before preparation
      # so a foreign id 404s even for a platform owner on another tenant URL.
      class SubscriptionOneTimePaymentsController < BaseController
        before_action :set_private_headers

        def create
          permitted = one_time_payment_params
          ::Billing::Invoice.for_current_customer.find(permitted[:invoice_id]) if permitted[:invoice_id].present?

          prepared = ::Billing::Activities::PrepareSubscriptionOneTimeInvoice.call(
            customer: current_customer,
            subscription: live_subscription,
            invoice_id: permitted[:invoice_id]
          )
          if prepared.status == :succeeded
            return redirect_to admin_settings_billing_invoice_path(current_customer_id, prepared.invoice),
                               status: :see_other,
                               notice: t("admin_settings.flash.billing.collection.succeeded")
          end
          return render_one_time_subscription_failure(prepared) unless prepared.status == :ready && prepared.invoice

          result = ::Billing::Activities::StartOneTimePayment.call(
            invoice: prepared.invoice,
            provider: permitted[:provider],
            openid: permitted[:openid],
            request: request
          )
          case result.status
          when :succeeded
            redirect_to admin_settings_billing_invoice_path(current_customer_id, prepared.invoice),
                        status: :see_other,
                        notice: t("admin_settings.flash.billing.collection.succeeded")
          when :action_required
            redirect_to admin_settings_billing_invoice_one_time_payment_path(current_customer_id, prepared.invoice),
                        status: :see_other
          when :pending
            redirect_to admin_settings_billing_invoice_one_time_payment_path(current_customer_id, prepared.invoice),
                        status: :see_other,
                        notice: t("admin_settings.flash.billing.collection.pending")
          else
            render_one_time_subscription_failure(result)
          end
        end

        private

        def set_private_headers
          response.headers["Cache-Control"] = "no-store, private"
          response.headers["Referrer-Policy"] = "no-referrer"
        end

        def one_time_payment_params
          nested = params[:one_time_payment]
          if nested.is_a?(ActionController::Parameters)
            nested.permit(:provider, :invoice_id, :openid)
          elsif nested.is_a?(Hash)
            ActionController::Parameters.new(nested).permit(:provider, :invoice_id, :openid)
          else
            params.permit(:provider, :invoice_id, :openid)
          end
        end

        def render_one_time_subscription_failure(result)
          assign_billing_result(result)
          @one_time_open = true
          @one_time_error = billing_failure_message(result)
          respond_to do |format|
            format.html do
              assign_subscription_overview
              flash.now[:alert] = @one_time_error
              render "admin/settings/billing/subscriptions/show", status: billing_failure_status(result)
            end
            format.json do
              render json: { status: result.status, reason: result.reason, error: @one_time_error },
                     status: billing_failure_status(result)
            end
          end
        end
      end
    end
  end
end
