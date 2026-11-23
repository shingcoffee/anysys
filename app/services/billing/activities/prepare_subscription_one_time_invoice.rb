# frozen_string_literal: true

module Billing
  module Activities
    class PrepareSubscriptionOneTimeInvoice
      PURPOSE_ORDER = Arel.sql("CASE purpose WHEN 'initial' THEN 0 WHEN 'renewal' THEN 1 ELSE 2 END")

      def self.call(customer:, subscription: nil, invoice_id: nil, at: Time.current)
        return resolve_invoice(customer: customer, invoice_id: invoice_id, at: at) if invoice_id.present?

        subscription ||= Entitlements.current_subscription(customer: customer)
        payable = first_payable_invoice(customer: customer, subscription: subscription, at: at)
        return Billing::Result.new(status: :ready, invoice: payable, subscription: payable.subscription) if payable

        if subscription && Subscription::LIVE_STATUSES.include?(subscription.status) &&
            !PlanChangePolicy.expiration_at(subscription: subscription, at: at)
          draft_result = finalize_accepted_draft(subscription: subscription, at: at)
          return draft_result if draft_result

          renewal_result = prepare_due_renewal(subscription: subscription, at: at)
          return renewal_result if renewal_result
        end

        Billing::Result.invalid(:invoice_not_payable, subscription: subscription)
      end

      def self.resolve_invoice(customer:, invoice_id:, at:)
        invoice = Invoice.unscoped_by_tenant.where(customer_id: customer.id).find_by(id: invoice_id)
        return Billing::Result.invalid(:invoice_not_payable) unless invoice

        if invoice.draft? && Subscription::LIVE_STATUSES.include?(invoice.subscription.status) &&
            PlanChangePolicy.accepted_invoice?(invoice: invoice, subscription: invoice.subscription)
          FinalizeInvoice.call(invoice: invoice)
        end
        invoice.reload
        return Billing::Result.new(status: :succeeded, invoice: invoice, subscription: invoice.subscription) if invoice.paid?
        unless PresentationFacts.invoice_collection(invoice: invoice, at: at)[:can_pay_one_time]
          return Billing::Result.invalid(:invoice_not_payable, invoice: invoice)
        end
        Billing::Result.new(status: :ready, invoice: invoice, subscription: invoice.subscription)
      end
      private_class_method :resolve_invoice

      def self.first_payable_invoice(customer:, subscription:, at:)
        scope = if subscription
          subscription.invoices
        else
          Invoice.unscoped_by_tenant.where(customer_id: customer.id)
        end
        scope.where(status: %w[open uncollectible]).order(PURPOSE_ORDER, :due_at, :id).detect do |invoice|
          PresentationFacts.invoice_collection(invoice: invoice, at: at)[:can_pay_one_time]
        end
      end
      private_class_method :first_payable_invoice

      def self.finalize_accepted_draft(subscription:, at:)
        draft = subscription.invoices.where(status: "draft").order(:id).detect do |candidate|
          PlanChangePolicy.accepted_invoice?(invoice: candidate, subscription: subscription)
        end
        return unless draft

        FinalizeInvoice.call(invoice: draft)
        draft.reload
        return Billing::Result.new(status: :succeeded, invoice: draft, subscription: subscription.reload) if draft.paid?
        return unless PresentationFacts.invoice_collection(invoice: draft, at: at)[:can_pay_one_time]
        Billing::Result.new(status: :ready, invoice: draft, subscription: subscription.reload)
      end
      private_class_method :finalize_accepted_draft

      def self.prepare_due_renewal(subscription:, at:)
        return unless %w[active trialing past_due].include?(subscription.status)
        boundary = PlanChangePolicy.period_boundary(subscription)
        return unless boundary && at >= boundary

        prepared = Renewal.prepare(subscription: subscription, at: at)
        return unless prepared.status == :invoice_ready && prepared.invoice

        FinalizeInvoice.call(invoice: prepared.invoice) if prepared.invoice.draft?
        invoice = prepared.invoice.reload
        return Billing::Result.new(status: :succeeded, invoice: invoice, subscription: subscription.reload) if invoice.paid?
        return unless PresentationFacts.invoice_collection(invoice: invoice, at: at)[:can_pay_one_time]
        Billing::Result.new(status: :ready, invoice: invoice, subscription: subscription.reload)
      end
      private_class_method :prepare_due_renewal
    end
  end
end
