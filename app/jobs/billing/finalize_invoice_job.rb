# frozen_string_literal: true

module Billing
  class FinalizeInvoiceJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true
    discard_on ActiveRecord::RecordNotFound

    def perform(invoice_id)
      raise ArgumentError, "invoice processing must run after domain commit" if Invoice.connection.transaction_open?

      invoice = Invoice.unscoped_by_tenant.find(invoice_id)
      Current.set(customer: invoice.customer) do
        return if invoice.paid? || invoice.void?
        if invoice.draft? && !Subscription::LIVE_STATUSES.include?(invoice.subscription.status)
          Activities::VoidInvoice.call(invoice: invoice)
          return
        end
        return if invoice.draft? && !PlanChangePolicy.accepted_invoice?(invoice: invoice, subscription: invoice.subscription)
        Activities::FinalizeInvoice.call(invoice: invoice)
        return if invoice.reload.paid? || invoice.void?

        Activities::ExpireOverdueSubscription.call(subscription: invoice.subscription, at: Time.current)
        Activities::CollectInvoice.call(invoice: invoice.reload, trigger: :initial)
      end
    end
  end
end
