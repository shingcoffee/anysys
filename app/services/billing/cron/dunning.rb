# frozen_string_literal: true

module Billing
  module Cron
    class Dunning
      def self.perform(at: Time.current)
        Invoice.unscoped_by_tenant.where(status: "open", collection_state: "retry_wait")
          .where("next_attempt_at <= ?", at).find_each do |invoice|
          Current.set(customer: invoice.customer) { Activities::CollectInvoice.call(invoice: invoice, trigger: :retry, at: at) }
        rescue StandardError => error
          Rails.logger.error("[billing.retry] invoice=#{invoice.id} #{error.class}: #{error.message}")
        end
        # Manual/blocked/no-attempt invoices owe the same immutable deadline.
        Invoice.unscoped_by_tenant.where(status: %w[open uncollectible], purpose: %w[initial renewal])
          .where("due_at <= ?", at).find_each do |invoice|
          Current.set(customer: invoice.customer) do
            Collector.with_invoice(invoice) do
              debt = Activities::RecordInvoiceDebt.call(invoice: invoice, at: at)
              Notifier.subscription_past_due(debt.subscription) if debt.status == :past_due
            end
            expire_with_notice(invoice.subscription, at)
          end
        rescue StandardError => error
          Rails.logger.error("[billing.deadline] invoice=#{invoice.id} #{error.class}: #{error.message}")
        end
        # Includes renewal/change holds without an open renewal debt row.
        Billing::Subscription.unscoped_by_tenant.live.where("current_period_end <= ?", at).find_each do |subscription|
          Current.set(customer: subscription.customer) { expire_with_notice(subscription, at) }
        rescue StandardError => error
          Rails.logger.error("[billing.expiry] subscription=#{subscription.id} #{error.class}: #{error.message}")
        end
      end

      def self.expire_with_notice(subscription, at)
        Billing::Result.transaction(subscription) do
          expired = Activities::ExpireOverdueSubscription.call(subscription: subscription, at: at)
          Notifier.subscription_cancelled(expired.subscription) if expired.status == :expired
        end
      end
      private_class_method :expire_with_notice
    end
  end
end
