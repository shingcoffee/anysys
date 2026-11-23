# frozen_string_literal: true

module Billing
  module Activities
    class GenerateInvoice
      def self.call(subscription:, purpose:, idempotency_key:, period_start:, period_end:, terms_snapshot:, plan_change: nil, extra_line_items: [])
        raise ArgumentError, "invalid invoice purpose/key" unless %w[initial renewal proration].include?(purpose.to_s) && idempotency_key.present?
        if plan_change && (plan_change.customer_id != subscription.customer_id || plan_change.billing_subscription_id != subscription.id)
          raise Payments::Errors::TenantMismatch, "plan change does not belong to subscription"
        end
        scope = Invoice.unscoped_by_tenant.where(customer_id: subscription.customer_id, idempotency_key: idempotency_key)
        existing = scope.first
        return replay(existing, subscription) if existing

        Billing::Result.transaction(subscription) do
          existing = scope.first
          next replay(existing, subscription) if existing
          terms = terms_snapshot.deep_stringify_keys.deep_dup
          required = Billing::PlanChangePolicy::PLAN_KEYS + %w[tax_rate_bps collection_mode dunning_schedule due_at]
          required += %w[billing_anchor_day billing_anchor_month] if purpose.to_s == "renewal"
          required.each { |key| terms.fetch(key) }
          unless terms.fetch("currency") == subscription.currency
            raise Payments::Errors::TenantMismatch, "invoice currency differs from accepted subscription"
          end
          invoice = scope.create!(billing_subscription_id: subscription.id, purpose: purpose,
            billing_plan_change_id: plan_change&.id, status: "draft", collection_state: "ready",
            period_start: period_start, period_end: period_end, due_at: Time.iso8601(terms.fetch("due_at")),
            currency: terms.fetch("currency").upcase, collection_mode: terms.fetch("collection_mode"), terms_snapshot: terms)
          Current.set(customer: subscription.customer) do
            I18n.with_locale(subscription.customer.locale.presence || I18n.default_locale) do
              unless purpose.to_s == "proration"
                amount = Integer(terms.fetch("amount_cents"))
                invoice.line_items.create!(customer_id: invoice.customer_id, kind: "subscription", quantity: 1,
                  unit_amount_cents: amount, amount_cents: amount,
                  description: I18n.t("comp_billing.invoice_lines.subscription", name: terms.fetch("name"), interval: terms.fetch("interval")))
              end
              extra_line_items.each { |attrs| invoice.line_items.create!(attrs.merge(customer_id: invoice.customer_id)) }
            end
          end
          invoice
        end
      rescue ActiveRecord::RecordNotUnique
        replay(scope.first!, subscription)
      end

      def self.replay(invoice, subscription)
        raise Payments::Errors::TenantMismatch, "invoice request identity belongs to another subscription" unless invoice.billing_subscription_id == subscription.id
        invoice
      end
      private_class_method :replay
    end
  end
end
