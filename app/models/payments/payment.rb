# frozen_string_literal: true

module Payments
  class Payment < ApplicationRecord
    self.table_name = "payments"

    include TenantScoped
    include Payments::NormalizesAmount

    normalizes_payment_amount :amount,
      currency: ->(payment) { payment.payment_order&.currency }

    FLOWS             = %w[qr h5 jsapi card].freeze
    STATUSES          = %w[created pending succeeded failed closed].freeze
    TERMINAL_STATUSES = %w[succeeded failed closed].freeze
    ATTEMPT_CONTEXT_KEY = "_attempt"

    # Invariant: once a payment reaches a terminal status it never regresses to
    # a non-terminal one (mark_pending!/mark_failed!/mark_closed! all no-op in
    # that case) — a late or replayed gateway notification must not undo a
    # final outcome. The one deliberate exception is succeeded itself: it is a
    # hard floor that nothing may overwrite, but failed/closed MAY still
    # transition to succeeded (see mark_succeeded!), because a cryptographically
    # verified PSP success outranks a locally pessimistic terminal state — a
    # late success after a local close/fail is real and Query/webhook paths
    # rely on being able to record it.

    belongs_to :payment_order, class_name: "Payments::Order",
                               foreign_key: :payment_order_id
    belongs_to :user, optional: true,
                      class_name: "Authentication::User",
                      foreign_key: :user_id
    has_many :payment_refunds, dependent: :destroy,
                               class_name: "Payments::Refund",
                               foreign_key: :payment_id
    has_many :payment_disputes, dependent: :destroy,
                                class_name: "Payments::Dispute",
                                foreign_key: :payment_id

    validates :provider,     presence: true,
                             inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }
    validates :flow,         presence: true, inclusion: { in: FLOWS }
    validates :out_trade_no, presence: true, uniqueness: true
    validates :amount,       presence: true, numericality: { greater_than: 0 }
    validates :status,       inclusion: { in: STATUSES }
    validates :customer_id,  presence: true

    def mark_pending!(prepay_payload)
      with_lock do
        return if status == "pending" || status.in?(TERMINAL_STATUSES)
        payload = prepay_payload.is_a?(Hash) ? prepay_payload.stringify_keys : prepay_payload
        payload[ATTEMPT_CONTEXT_KEY] = attempt_context if payload.is_a?(Hash) && attempt_context.present?
        update!(status: "pending", prepay_payload: payload)
      end
    end

    # Local, committed identity for the remote operation. Never sent to the PSP.
    def attempt_context
      prepay_payload.is_a?(Hash) ? prepay_payload.fetch(ATTEMPT_CONTEXT_KEY, {}) : {}
    end

    BILLING_ORDER_REF_PREFIX = "billing-inv-"

    # Invoice collection is stored on the platform customer so the PSP merchant
    # account can charge it. The Payments module must not list or refund those
    # rows; Billing owns that ledger.
    scope :commerce, -> {
      billing_order_ids = Payments::Order.unscoped_by_tenant
                                         .where("external_ref LIKE ?", "#{BILLING_ORDER_REF_PREFIX}%")
                                         .select(:id)
      where.not(payment_order_id: billing_order_ids)
    }

    def billing_collection?
      attempt_context["operation"] == "billing_collection" ||
        payment_order&.external_ref.to_s.start_with?(BILLING_ORDER_REF_PREFIX)
    end

    def merchant_account_id = attempt_context["merchant_account_id"]

    # True when an off-session charge stalled on issuer authentication (SCA) and
    # is awaiting the member to complete 3DS on-session.
    def requires_action?
      status == "pending" && prepay_payload.is_a?(Hash) && prepay_payload["requires_action"] == true
    end

    # The Stripe PaymentIntent client_secret to hand to Stripe.js so the member
    # can finish authentication; nil unless this payment requires action.
    def recovery_client_secret
      requires_action? ? prepay_payload["client_secret"] : nil
    end

    # The order's own record changes (Payments::PaidWriteback) run only when
    # this payment is the one that settles it.
    def mark_succeeded!(psp_id:, at:, notify:)
      with_lock do
        return if status == "succeeded"
        update!(status: "succeeded", psp_transaction_id: psp_id, paid_at: at, raw_notify: notify)
        settled = payment_order.with_lock { payment_order.mark_paid!(at) }
        Payments::PaidWriteback.call(payment: self) if settled
      end
    end

    def mark_failed!(reason:, notify: {})
      with_lock do
        return if status.in?(TERMINAL_STATUSES)
        update!(status: "failed", failure_reason: reason, raw_notify: notify)
        payment_order.with_lock { payment_order.mark_failed! }
      end
    end

    def mark_closed!
      with_lock do
        return if status.in?(TERMINAL_STATUSES)
        update!(status: "closed", closed_at: Time.zone.now)
      end
    end
  end
end
