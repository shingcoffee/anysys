# frozen_string_literal: true

module Sms
  class BackendReceipt < ApplicationRecord
    self.table_name = "sms_backend_receipts"

    validates :credential_id, :provider, :event_key, presence: true
    scope :pending, -> { where(processed_at: nil) }
    scope :for_customer, ->(id) { where(customer_id: id) }
  end
end
