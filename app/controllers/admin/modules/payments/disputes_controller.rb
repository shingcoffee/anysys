# frozen_string_literal: true

module Admin
  module Modules
    module Payments
      # Read-only admin view of card disputes / chargebacks for the tenant.
      # Authorization + tenant context are enforced by the global RouteAuthorization
      # (admin/owner only under /:cid/admin/…); every query is customer-scoped.
      class DisputesController < BaseController
        dashboard_menu_item :modules

        def index
          @disputes = scoped_disputes
        end

        private

        def scoped_disputes
          ::Payments::Dispute
            .for_current_customer
            .where(payment_id: ::Payments::Payment.commerce.select(:id))
            .includes(payment: :payment_order)
            .order(opened_at: :desc, created_at: :desc)
            .limit(100)
        end
      end
    end
  end
end
