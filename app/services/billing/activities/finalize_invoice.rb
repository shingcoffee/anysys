# frozen_string_literal: true

module Billing
  module Activities
    class FinalizeInvoice
      def self.call(invoice:)
        tries = 0
        nested = Invoice.connection.transaction_open?
        begin
          Collector.with_invoice(invoice) do
            if invoice.draft?
              # The write claim also acquires SQLite's writer boundary. Unique
              # invoice/cycle/sequence indexes arbitrate competing processes.
              Invoice.where(id: invoice.id, status: "draft").update_all(updated_at: Time.current)
              invoice.recompute_totals!
              discount = Billing::Discounts.reserve_for_invoice!(invoice: invoice)
              locale = invoice.customer.locale.presence || I18n.default_locale
              I18n.with_locale(locale) do
                if discount && discount[:discount_cents].positive?
                  # Discounts owns the persisted redemption/cycle reservation.
                  add_line(invoice, "discount", -discount[:discount_cents], I18n.t(discount[:description_key], **discount[:description_values]))
                end
              end
              invoice.recompute_totals!
              rate = Integer(invoice.terms_snapshot.fetch("tax_rate_bps"))
              tax = [invoice.subtotal_cents - invoice.discount_cents, 0].max * rate / 10_000
              I18n.with_locale(locale) do
                add_line(invoice, "tax", tax, I18n.t("comp_billing.invoice_lines.tax", rate: (BigDecimal(rate.to_s) / 100).to_s("F"))) if tax.positive?
              end
              invoice.recompute_totals!
              invoice.update!(status: "open", issued_at: Time.current,
                number: InvoiceNumber.allocate!(customer_id: invoice.customer_id),
                collection_state: invoice.effective_collection_mode == "manual" ? "manual" : "ready")
              Notifier.invoice_issued(invoice)
            end
            MarkInvoicePaid.call(invoice: invoice, source: :zero) if invoice.open? && invoice.total_cents.zero?
          end
        rescue ActiveRecord::StatementInvalid => error
          tries += 1
          raise if nested || !error.cause.is_a?(SQLite3::BusyException) || tries >= InvoiceNumber::MAX_RETRIES
          sleep(0.02 * tries)
          retry
        end
        invoice.reload
      end

      def self.add_line(invoice, kind, amount, description)
        invoice.line_items.create!(customer_id: invoice.customer_id, kind: kind, quantity: 1,
          unit_amount_cents: amount, amount_cents: amount, description: description)
      end
      private_class_method :add_line
    end
  end
end
