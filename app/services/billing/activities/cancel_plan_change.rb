# frozen_string_literal: true

module Billing
  module Activities
    class CancelPlanChange
      def self.call(subscription:, plan_change:)
        Result.transaction(subscription) do
          change = subscription.plan_changes.find_by(id: plan_change.id, customer_id: subscription.customer_id)
          next Result.new(status: :conflict, reason: :plan_change_not_found, subscription: subscription) unless change
          next Result.new(status: :cancelled, subscription: subscription, plan_change: change) unless %w[scheduled awaiting_payment].include?(change.status)

          # A scheduled target may already be frozen into an unpaid renewal.
          # Cancel that invoice too; settlement must never apply a cancelled target.
          conflict = nil
          change.invoices.order(:id).each do |invoice|
            result = VoidInvoice.call(invoice: invoice)
            unless %i[voided unchanged].include?(result.status) && invoice.reload.status == "void"
              conflict = Result.new(status: :conflict, subscription: subscription, plan_change: change,
                invoice: invoice, reason: :collection_in_flight)
              break
            end
          end
          next conflict if conflict
          change.update!(status: "cancelled", cancelled_at: Time.current)
          Result.new(status: :cancelled, subscription: subscription, plan_change: change)
        end
      end
    end
  end
end
