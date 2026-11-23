# frozen_string_literal: true

module Billing
  module Cron
    class CollectDueInvoices
      def self.perform(at: Time.current)
        Invoice.unscoped_by_tenant.where(status: "open", collection_state: "ready", attempt_count: 0)
          .where("due_at <= ?", at).find_each do |invoice|
          Current.set(customer: invoice.customer) { Activities::CollectInvoice.call(invoice: invoice, trigger: :initial, at: at) }
        rescue StandardError => error
          Rails.logger.error("[billing.initial] invoice=#{invoice.id} #{error.class}: #{error.message}")
        end
      end
    end
  end
end
