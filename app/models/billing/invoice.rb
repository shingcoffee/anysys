# frozen_string_literal: true

module Billing
  class Invoice < ApplicationRecord
    self.table_name = "billing_invoices"

    include TenantScoped

    STATUSES = %w[draft open paid void uncollectible].freeze
    COLLECTION_STATES = %w[ready manual blocked pending requires_action retry_wait exhausted settled stopped].freeze
    FINANCIAL_ATTRIBUTES = %w[number issued_at due_at period_start period_end currency subtotal_cents discount_cents tax_cents total_cents collection_mode purpose idempotency_key terms_snapshot billing_plan_change_id billing_coupon_redemption_id coupon_cycle_number billing_coupon_id billing_subscription_id customer_id].freeze

    belongs_to :subscription, class_name: "Billing::Subscription", foreign_key: :billing_subscription_id
    belongs_to :coupon,       class_name: "Billing::Coupon",        foreign_key: :billing_coupon_id, optional: true
    belongs_to :plan_change, class_name: "Billing::PlanChange", foreign_key: :billing_plan_change_id, optional: true
    belongs_to :payment, class_name: "Payments::Payment", optional: true
    has_many :collection_attempts, class_name: "Billing::CollectionAttempt", foreign_key: :billing_invoice_id, dependent: :restrict_with_exception
    has_many :line_items, class_name: "Billing::InvoiceLineItem", foreign_key: :billing_invoice_id, dependent: :restrict_with_exception

    validates :customer_id, presence: true
    validates :status,      inclusion: { in: STATUSES }
    validates :collection_state, inclusion: { in: COLLECTION_STATES }
    validates :purpose, inclusion: { in: %w[initial renewal proration] }
    validates :currency, inclusion: { in: %w[USD CNY] }
    validate :issued_terms_are_immutable, on: :update
    before_destroy { throw(:abort) unless draft? }

    scope :collectible, -> {
      now = Time.zone.now
      where(status: "open")
        .where("due_at <= ?", now)
        .where(collection_state: "ready", attempt_count: 0)
        .where(collection_override_mode: [nil, "gateway"])
    }

    # Recomputes subtotal / discount / tax / total from line items.
    # - subtotal_cents = sum of subscription + proration line items
    # - discount_cents = sum of (absolute values of) discount line items
    # - tax_cents      = sum of tax line items
    # - total_cents    = subtotal - discount + tax
    def recompute_totals!
      raise ArgumentError, "issued invoice is immutable" unless draft?
      sub_total  = line_items.where(kind: %w[subscription proration]).sum(:amount_cents)
      disc_total = line_items.where(kind: "discount").sum(:amount_cents).abs
      tax_total  = line_items.where(kind: "tax").sum(:amount_cents)

      update!(
        subtotal_cents: sub_total,
        discount_cents: disc_total,
        tax_cents:      tax_total,
        total_cents:    [sub_total - disc_total + tax_total, 0].max
      )
    end

    def effective_collection_mode = collection_override_mode.presence || terms_snapshot.fetch("collection_mode")
    def collection_deadline = Billing::PlanChangePolicy.request_deadline(self)

    # Convenience predicates
    def draft?          = status == "draft"
    def open?           = status == "open"
    def paid?           = status == "paid"
    def void?           = status == "void"
    def uncollectible?  = status == "uncollectible"

    private

    def issued_terms_are_immutable
      return if status_in_database == "draft"
      errors.add(:base, :invalid) if (changes_to_save.keys & FINANCIAL_ATTRIBUTES).any?
    end
  end
end
