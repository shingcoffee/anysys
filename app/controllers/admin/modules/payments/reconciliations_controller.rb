# frozen_string_literal: true

module Admin
  module Modules
    module Payments
    class ReconciliationsController < BaseController
      dashboard_menu_item :modules
      def index
        @bills = ::Payments::ReconciliationBill.for_current_customer.order(bill_date: :desc).limit(60)
      end

      def show
        @bill = ::Payments::ReconciliationBill.for_current_customer.find(params[:id])
      end

      # Streams the attached settlement file through the admin-gated, tenant-scoped
      # request rather than exposing ActiveStorage's public blob route (which sits
      # outside the /:cid/admin/ authorization boundary). Cross-tenant ids 404 via
      # for_current_customer; bills with no file 404 via the attached? guard.
      def download
        bill = ::Payments::ReconciliationBill.for_current_customer.find(params[:id])
        return head :not_found unless bill.bill_file.attached?

        send_data bill.bill_file.download,
                  filename: bill.bill_file.filename.to_s,
                  type: bill.bill_file.content_type,
                  disposition: "attachment"
      end
    end
    end
  end
end
