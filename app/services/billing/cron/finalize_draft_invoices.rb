# frozen_string_literal: true

module Billing
  module Cron
    class FinalizeDraftInvoices
      # Draft rows, not queue delivery, are the durable acceptance authority.
      # Finalization is database-only; collection is queued after commit and B's
      # initial claim/attempt identity arbitrates repeated jobs and concurrent scans.
      def self.perform
        Invoice.unscoped_by_tenant.where(status: "draft").find_each do |invoice|
          Current.set(customer: invoice.customer) do
            if Subscription::LIVE_STATUSES.include?(invoice.subscription.status)
              next unless PlanChangePolicy.accepted_invoice?(invoice: invoice, subscription: invoice.subscription)
              Activities::FinalizeInvoice.call(invoice: invoice)
              Result.collect_after_commit(invoice) unless invoice.reload.paid?
            else
              Activities::VoidInvoice.call(invoice: invoice)
            end
          end
        rescue StandardError => error
          Rails.logger.error("[billing.drafts] invoice_id=#{invoice.id} #{error.class}: #{error.message}")
        end
      end
    end
  end
end
