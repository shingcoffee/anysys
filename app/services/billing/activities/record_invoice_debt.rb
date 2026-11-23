# frozen_string_literal: true

module Billing
  module Activities
    class RecordInvoiceDebt
      def self.call(invoice:, at:)
        subscription = Subscription.unscoped_by_tenant.find(invoice.billing_subscription_id)
        Result.transaction(subscription) do
          invoice.reload
          unless invoice.customer_id == subscription.customer_id && invoice.purpose == "renewal" &&
              %w[open uncollectible].include?(invoice.status) && invoice.due_at && at >= invoice.due_at &&
              invoice.period_start == PlanChangePolicy.period_boundary(subscription) && %w[active trialing past_due].include?(subscription.status)
            next Result.new(status: :unchanged, subscription: subscription, invoice: invoice)
          end
          subscription.update!(status: "past_due", past_due_at: subscription.past_due_at || invoice.due_at)
          Result.new(status: :past_due, subscription: subscription, invoice: invoice)
        end
      end
    end
  end
end
