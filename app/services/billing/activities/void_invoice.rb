# frozen_string_literal: true

module Billing
  module Activities
    class VoidInvoice
      def self.call(invoice:)
        Collector.with_invoice(invoice) do
          return Billing::Result.new(status: :unchanged, invoice: invoice) if invoice.void?
          unless (invoice.draft? || invoice.open? || invoice.uncollectible?) && !Collector.unresolved?(invoice)
            return Billing::Result.new(status: :conflict, invoice: invoice, reason: :collection_in_flight)
          end
          invoice.update!(status: "void", collection_state: "stopped", next_attempt_at: nil, collection_claimed_at: nil)
          Billing::Result.new(status: :voided, invoice: invoice)
        end
      end
    end
  end
end
