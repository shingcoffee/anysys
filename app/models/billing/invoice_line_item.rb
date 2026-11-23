# frozen_string_literal: true

module Billing
  class InvoiceLineItem < ApplicationRecord
    self.table_name = "billing_invoice_line_items"

    include TenantScoped

    KINDS = %w[subscription proration discount tax].freeze

    belongs_to :invoice, class_name: "Billing::Invoice", foreign_key: :billing_invoice_id

    validates :customer_id,     presence: true
    validates :description,     presence: true
    validates :kind,            inclusion: { in: KINDS }
    validates :quantity,        numericality: { greater_than: 0, only_integer: true }
    validates :unit_amount_cents, numericality: { only_integer: true }
    validates :amount_cents,    numericality: { only_integer: true }
    validate :invoice_must_be_draft
    before_destroy :require_draft_invoice

    private

    def invoice_must_be_draft
      original = persisted? && Billing::Invoice.unscoped_by_tenant.find_by(id: billing_invoice_id_in_database)
      errors.add(:base, :invalid) unless invoice&.draft? && (!original || original.draft?)
    end

    def require_draft_invoice
      throw(:abort) unless invoice.draft?
    end
  end
end
