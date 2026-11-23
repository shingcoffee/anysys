# frozen_string_literal: true

module Payments
  class Refund < ApplicationRecord
    self.table_name = "payment_refunds"

    include TenantScoped
    include Payments::NormalizesAmount

    normalizes_payment_amount :amount,
      currency: ->(refund) { refund.payment&.payment_order&.currency }

    STATUSES          = %w[requested processing succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    # Invariant: once a refund reaches a terminal status it never regresses to
    # a non-terminal one (mark_processing!/mark_failed! no-op in that case) — a
    # late or replayed gateway notification must not undo a final outcome.
    # succeeded is a hard floor nothing may overwrite; failed MAY still
    # transition to succeeded (see mark_succeeded!) since a verified PSP
    # success outranks a locally pessimistic terminal state.

    belongs_to :payment, class_name: "Payments::Payment",
                         foreign_key: :payment_id

    validates :out_refund_no, presence: true, uniqueness: true
    validates :amount,        presence: true, numericality: { greater_than: 0 }
    validates :status,        inclusion: { in: STATUSES }
    validates :customer_id,   presence: true

    def mark_processing!(psp_refund_id: nil, notify: {})
      with_lock do
        return self if status == "processing" || status.in?(TERMINAL_STATUSES)
        update!(status: "processing", psp_refund_id: psp_refund_id, raw_notify: notify)
      end
    end

    def mark_succeeded!(at:, psp_refund_id:, notify:)
      with_lock do
        return if status == "succeeded"
        update!(status: "succeeded", succeeded_at: at,
                psp_refund_id: psp_refund_id, raw_notify: notify)
        recalc_order_status!
      end
    end

    def mark_failed!(notify:)
      with_lock do
        return if status.in?(TERMINAL_STATUSES)
        update!(status: "failed", failed_at: Time.zone.now, raw_notify: notify)
      end
    end

    private

    def recalc_order_status!
      order = payment.payment_order
      order.with_lock do
        refunded = order.payments
                        .joins(:payment_refunds)
                        .where(payment_refunds: { status: "succeeded" })
                        .sum("payment_refunds.amount")
        new_status = refunded >= order.amount ? "refunded" : "partial_refund"
        order.update!(status: new_status)
      end
    end
  end
end
