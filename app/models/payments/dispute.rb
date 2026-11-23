# frozen_string_literal: true

module Payments
  # A card dispute / chargeback for a captured payment. Orthogonal to the
  # payment's own lifecycle: the money remains captured until a dispute is lost,
  # so this is a linked record, not a payment status. One row per PSP dispute id
  # (unique), upserted as the dispute progresses (created → under_review → won/lost).
  class Dispute < ApplicationRecord
    include JsonSerializable
    include TenantScoped
    include Payments::NormalizesAmount

    normalizes_payment_amount :amount,
      currency: ->(dispute) { dispute.payment&.payment_order&.currency }

    self.table_name = "payment_disputes"

    # open / under_review — funds provisionally held; won — merchant kept the
    # funds; lost — charged back (funds reversed); closed — withdrawn/expired.
    STATUSES = %w[open under_review won lost closed].freeze
    OPEN_STATUSES     = %w[open under_review].freeze
    RESOLVED_STATUSES = %w[won lost closed].freeze

    json_attribute :raw, default: {}

    belongs_to :payment, class_name: "Payments::Payment", foreign_key: :payment_id

    validates :provider,       presence: true
    validates :psp_dispute_id, presence: true, uniqueness: { scope: :provider }
    validates :status,         inclusion: { in: STATUSES }
    validates :amount,         numericality: true
    validates :customer_id,    presence: true

    scope :open,     -> { where(status: OPEN_STATUSES) }
    scope :resolved, -> { where(status: RESOLVED_STATUSES) }

    def resolved? = status.in?(RESOLVED_STATUSES)
  end
end
