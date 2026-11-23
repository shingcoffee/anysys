# frozen_string_literal: true

module Billing
  class Plan < ApplicationRecord
    self.table_name = "billing_plans"

    INTERVALS = %w[monthly yearly].freeze

    has_many :plan_limits,
             class_name:   "Billing::PlanLimit",
             foreign_key:  :billing_plan_id,
             dependent:    :destroy,
             inverse_of:   :plan

    validates :code,        presence: true, uniqueness: true
    validates :name,        presence: true
    validates :amount_usd,  numericality: { greater_than_or_equal_to: 0 }
    validates :amount_cny,  numericality: { greater_than_or_equal_to: 0 }
    validates :interval,    inclusion: { in: INTERVALS }

    has_many :subscriptions, class_name: "Billing::Subscription", foreign_key: :billing_plan_id, dependent: :restrict_with_error
    has_many :outgoing_changes, class_name: "Billing::PlanChange", foreign_key: :from_plan_id, dependent: :restrict_with_error
    has_many :incoming_changes, class_name: "Billing::PlanChange", foreign_key: :to_plan_id, dependent: :restrict_with_error

    scope :active,  -> { where(active: true, archived_at: nil) }
    scope :ordered, -> { order(:position, :id) }

    def self.default_plan
      active.find_by(is_default: true)
    end

    def monthly? = interval == "monthly"
    def yearly?  = interval == "yearly"

    # Decimal price (whole currency units) for the given currency.
    def amount_for(currency)
      case currency.to_s.upcase
      when "CNY" then amount_cny
      when "USD" then amount_usd
      else raise ArgumentError, "Unsupported billing currency"
      end
    end

    # Integer minor units (cents) for the Payments boundary — Payments::Order /
    # Payment / Subscription store amounts in cents, as PSPs require.
    def price_cents_for(currency)
      Money.from_amount(amount_for(currency).to_d, currency.to_s.upcase).cents
    end

    def limit_for(item_key)
      pl = plan_limits.find { |l| l.item_key == item_key.to_s }
      pl ? pl.limit_value : Billing::PlanLimit::UNLIMITED
    end

    def free? = amount_usd.to_d.zero? && amount_cny.to_d.zero?

    def referenced? = subscriptions.exists? || outgoing_changes.exists? || incoming_changes.exists?
  end
end
