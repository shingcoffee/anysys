# frozen_string_literal: true

module Admin
  module Modules
    module Payments
    class TransactionsController < BaseController
      dashboard_menu_item :modules
      def index
        @payments = scoped_payments.includes(:payment_order, :payment_refunds, :payment_disputes)
                                   .order(created_at: :desc).limit(100)
      end

      def show
        @payment = scoped_payments.find(params[:id])
      end

      private

      def scoped_payments
        ::Payments::Payment.for_current_customer.commerce
      end
    end
    end
  end
end
