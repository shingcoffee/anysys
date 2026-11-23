# frozen_string_literal: true

module Billing
  module Cron
    class ReconcileCollections
      def self.perform(at: Time.current)
        # The intent transaction may commit before its finalization callback is
        # dispatched. Recover only that subscription's accepted draft intent;
        # finalization locks and identities preserve one number/coupon cycle.
        Invoice.unscoped_by_tenant.where(status: "draft").find_each do |invoice|
          Collector.with_invoice(invoice) do
            # Another worker may have issued the row after this scan selected it.
            # Only the winning draft transition schedules collection disposition.
            next unless invoice.draft?
            subscription = invoice.subscription
            next unless Billing::Subscription::LIVE_STATUSES.include?(subscription.status)
            next if Billing::PlanChangePolicy.expiration_at(subscription: subscription, at: at)
            next unless accepted_draft?(invoice, subscription)
            Activities::FinalizeInvoice.call(invoice: invoice)
            # Reuse A's central finalization/expiry/initial-collection job. The
            # callback only enqueues after this outer finalization commits.
            Result.collect_after_commit(invoice) unless invoice.reload.paid?
          end
        rescue StandardError => error
          Rails.logger.error("[billing.draft_reconcile] invoice=#{invoice.id} #{error.class}: #{error.message}")
        end
        live_ids = CollectionAttempt.unscoped_by_tenant.inflight.where("reconcile_at IS NULL OR reconcile_at <= ?", at).select(:billing_invoice_id)
        paid_ids = CollectionAttempt.unscoped_by_tenant.joins(:invoice, :payment).where(payments: { status: "succeeded" })
          .where("billing_invoices.status != 'paid' OR (billing_invoices.entitlements_applied_at IS NULL AND billing_invoices.settlement_review_code IS NULL) OR billing_invoices.payment_id IS NULL OR billing_collection_attempts.payment_id != billing_invoices.payment_id OR billing_collection_attempts.state != 'succeeded'")
          .select(:billing_invoice_id)
        Invoice.unscoped_by_tenant.where(id: live_ids).or(Invoice.unscoped_by_tenant.where(id: paid_ids)).find_each do |invoice|
          Current.set(customer: invoice.customer) { Activities::CollectInvoice.call(invoice: invoice, trigger: :reconcile, at: at) }
        rescue StandardError => error
          Rails.logger.error("[billing.reconcile] invoice=#{invoice.id} #{error.class}: #{error.message}")
        end
        Invoice.unscoped_by_tenant.where(status: "paid", settlement_source: %w[zero manual], entitlements_applied_at: nil, settlement_review_code: nil).find_each do |invoice|
          Current.set(customer: invoice.customer) do
            actor = Authentication::User.unscoped.find_by(id: invoice.settled_by_id) if invoice.settlement_source == "manual"
            Activities::MarkInvoicePaid.call(invoice: invoice, source: invoice.settlement_source,
              actor: actor, reference: invoice.settlement_reference, note: invoice.settlement_note)
          end
        rescue StandardError => error
          Rails.logger.error("[billing.local_projection] invoice=#{invoice.id} #{error.class}: #{error.message}")
        end
        PaymentMethod.unscoped_by_tenant.where(status: %w[pending failed]).find_each do |method|
          Current.set(customer: method.customer) do
            if method.authorization_expires_at && method.authorization_expires_at <= at
              Activities::RemovePaymentMethod.call(payment_method: method)
            elsif method.authorization_reference.blank? && method.provider == "stripe"
              Activities::SetUpPaymentMethod.call(customer: method.customer, actor: method.authorized_by, provider: method.provider,
                request_key: method.request_key, return_url: Rails.application.routes.url_helpers.admin_settings_billing_payment_methods_url(
                  customer_id: method.customer_id, host: ENV.fetch("APP_HOST", "localhost")))
            else
              PaymentAuthorization.confirm!(payment_method: method)
            end
          end
        rescue StandardError => error
          Rails.logger.error("[billing.setup_reconcile] method=#{method.id} #{error.class}: #{error.message}")
        end
      end

      def self.accepted_draft?(invoice, subscription)
        return false if Providers.invoice_identity_reason(invoice)
        PlanChangePolicy.accepted_invoice?(invoice: invoice, subscription: subscription)
      end
      private_class_method :accepted_draft?
    end
  end
end
