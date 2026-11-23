# frozen_string_literal: true

module Admin
  module Modules
    module Payments
      class RefundsController < BaseController
        dashboard_menu_item :modules

        # Maps a RefundNotAllowed#code to its admin-facing flash key. Any code not
        # listed here (and every ApiError) falls back to the generic failure flash
        # — the developer-oriented exception message never reaches the admin.
        REFUND_FAILURE_KEYS = {
          not_captured:      "comp_payments.flash.refund_not_captured",
          non_positive:      "comp_payments.flash.refund_amount_not_positive",
          exceeds_remainder: "comp_payments.flash.refund_exceeds_remainder",
          billing_collection: "comp_payments.flash.refund_billing_collection"
        }.freeze

        def create
          payment = ::Payments::Payment.for_current_customer.commerce.find(params[:transaction_id])
          refund = ::Payments::Activities::Refund.call(
            customer: current_customer,
            payment: payment,
            amount: params[:amount],
            reason: params[:reason]
          )
          redirect_to admin_modules_payments_transactions_path(current_customer_id),
                      **refund_outcome_flash(refund)
        rescue ::Payments::Errors::RefundNotAllowed => e
          redirect_to admin_modules_payments_transactions_path(current_customer_id),
                      alert: refund_failure_alert(e)
        rescue ::Payments::Errors::Error
          redirect_to admin_modules_payments_transactions_path(current_customer_id),
                      alert: t("comp_payments.flash.refund_failed")
        end

        private

        def refund_outcome_flash(refund)
          case refund.status
          when "succeeded"
            { notice: t("comp_payments.flash.refunded") }
          when "processing", "requested"
            { notice: t("comp_payments.flash.refund_processing") }
          else
            { alert: t("comp_payments.flash.refund_failed") }
          end
        end

        def refund_failure_alert(error)
          key = REFUND_FAILURE_KEYS[error.code]
          return t("comp_payments.flash.refund_failed") unless key

          t(key, **error.details.symbolize_keys)
        end
      end
    end
  end
end
