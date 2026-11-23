# frozen_string_literal: true

module Billing
  module Cron
    class RenewSubscriptions
      def self.perform
        FinalizeDraftInvoices.perform
        Subscription.unscoped_by_tenant.due_for_renewal.find_each do |subscription|
          Current.set(customer: subscription.customer) do
            result = Renewal.prepare(subscription: subscription)
            Result.collect_after_commit(result.invoice) if result.status == :invoice_ready
          end
        rescue StandardError => error
          Rails.logger.error("[billing.renewal] subscription_id=#{subscription.id} #{error.class}: #{error.message}")
        end
      end
    end
  end
end
