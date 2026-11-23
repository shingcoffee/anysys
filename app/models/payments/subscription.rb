# frozen_string_literal: true

module Payments
  class Subscription < ApplicationRecord
    self.table_name = "payment_subscriptions"

    include TenantScoped
    include Payments::NormalizesAmount

    normalizes_payment_amount :amount, currency: :currency

    CYCLES   = %w[daily weekly monthly yearly].freeze
    STATUSES = %w[pending_sign active paused cancelled expired].freeze
    TERMINAL_STATUSES = %w[cancelled expired].freeze

    belongs_to :payment_method, class_name: "Payments::PaymentMethod", optional: true

    validates :provider, inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }
    validates :external_ref, presence: true, uniqueness: { scope: :customer_id }
    validates :plan_name,    presence: true
    validates :amount,       numericality: { greater_than: 0 }
    validates :cycle,        inclusion: { in: CYCLES }
    validates :status,       inclusion: { in: STATUSES }
    validates :customer_id,  presence: true
    validates :currency, presence: true,
      inclusion: { in: ->(_) { Payments::Gateways.all.flat_map(&:supported_currencies).uniq } }

    scope :payments_managed, -> { where(managed_by: "payments") }
    scope :due_now, -> { payments_managed.where(status: "active").where("next_charge_at <= ?", Time.zone.now) }

    def mark_active!(psp_agreement_id:, at:)
      with_lock do
        return if status == "active" || status.in?(TERMINAL_STATUSES)
        update!(status: "active", psp_agreement_id: psp_agreement_id,
                signed_at: at, next_charge_at: billing_owned? ? nil : next_charge_time_from(at))
      end
    end

    def mark_cancelled!
      with_lock do
        return if status.in?(TERMINAL_STATUSES)
        update!(status: "cancelled", cancelled_at: Time.zone.now)
      end
    end

    # Dunning: taken out of the active/due population when a recurring charge
    # cannot proceed (issuer demands interactive auth, or the vaulted card is no
    # longer chargeable). A paused subscription is not selected by #due_now, so it
    # stops retrying every cron tick until a human/webhook reactivates it.
    def mark_paused!(expected_anchor: next_charge_at)
      with_lock do
        return unless managed_by == "payments" && status == "active" && next_charge_at == expected_anchor
        update!(status: "paused")
      end
    end

    def reactivate_paused!(at: Time.current)
      with_lock do
        return unless managed_by == "payments" && status == "paused"
        update!(status: "active", next_charge_at: next_charge_time_from(at))
      end
    end

    # Advance from the scheduled anchor (previous next_charge_at), NOT wall-clock
    # now, so the billing date does not drift later every cycle and a cron that
    # runs slightly late still bills for the correct period.
    def advance_next_charge!(expected_anchor: next_charge_at)
      with_lock do
        return unless managed_by == "payments" && status == "active" && next_charge_at == expected_anchor
        anchor = next_charge_at || Time.zone.now
        update!(next_charge_at: next_charge_time_from(anchor))
      end
    end

    # Billing's mandate rows belong to invoice collection, not this scheduler.
    # One typed ownership authority; B stamps billing mandates at creation.
    def billing_owned?
      managed_by == "billing"
    end

    # True when the subscription is charged off-session against a vaulted card
    # token rather than through a PSP-managed agreement (Alipay/WeChat recurring).
    def card_recurring? = payment_method_id.present?

    # One billing cycle after t. Public so callers that must re-anchor from a
    # specific moment (e.g. SCA reactivation) can reuse the period arithmetic.
    def next_charge_time_from(t)
      case cycle
      when "daily"   then t + 1.day
      when "weekly"  then t + 1.week
      when "monthly" then t + 1.month
      when "yearly"  then t + 1.year
      end
    end
  end
end
