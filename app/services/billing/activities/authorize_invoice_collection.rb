# frozen_string_literal: true

module Billing
  module Activities
    class AuthorizeInvoiceCollection
      def self.call(invoice:, actor:, mode:, note:)
        Collector.with_invoice(invoice) do
          reason = if !actor&.owner? || actor.customer_id != Collector::PLATFORM_OWNER_CUSTOMER_ID
            :owner_required
          elsif !Billing::Settings::COLLECTION_MODES.include?(mode.to_s) || note.blank?
            :invalid_collection_authorization
          elsif !%w[open uncollectible].include?(invoice.status)
            :invoice_not_payable
          elsif Collector.unresolved?(invoice)
            :collection_in_flight
          end
          return Billing::Result.new(status: :invalid, invoice: invoice, reason: reason) if reason
          invoice.update!(collection_override_mode: mode, collection_override_by_id: actor.id,
            collection_override_at: Time.current, settlement_note: note, next_attempt_at: nil,
            collection_state: mode.to_s == "manual" ? "manual" : "ready")
          Notifier.collection_authorized(invoice)
          Billing::Result.new(status: :authorized, invoice: invoice)
        end
      end
    end
  end
end
