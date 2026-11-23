# frozen_string_literal: true

module Emails
  # Platform ingress: no tenant is known until a vendor ID is correlated.
  class BackendReceipt < ApplicationRecord
    self.table_name = "email_backend_receipts"

    validates :credential_id, :provider, :event_key, presence: true
    scope :pending, -> { where(processed_at: nil) }
    scope :for_customer, ->(id) { where(customer_id: id) }
  end
end
