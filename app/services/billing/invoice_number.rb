# frozen_string_literal: true

module Billing
  module InvoiceNumber
    MAX_RETRIES = 4

    def self.allocate!(customer_id:)
      raise ArgumentError, "allocate invoice number inside finalization transaction" unless Invoice.connection.transaction_open?

      now = Time.current
      InvoiceSequence.insert_all([{ customer_id: customer_id, last_value: 0, created_at: now, updated_at: now }], unique_by: :customer_id)
      scope = InvoiceSequence.unscoped_by_tenant.where(customer_id: customer_id)
      scope.update_all(["last_value = last_value + 1, updated_at = ?", now])
      "INV-#{customer_id}-#{scope.pick(:last_value).to_s.rjust(5, '0')}"
    end
  end
end
