# frozen_string_literal: true

module Billing
  class InvoiceSequence < ApplicationRecord
    self.table_name = "billing_invoice_sequences"
    include TenantScoped
    validates :customer_id, presence: true
    validates :last_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
