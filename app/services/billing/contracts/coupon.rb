# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    # Validates platform CRUD inputs for a billing coupon.
    class Coupon < Reform::Form
      property :code
      property :name
      property :discount_type
      property :percent_off
      property :amount_off_cents
      property :currency
      property :duration
      property :duration_in_cycles
      property :max_redemptions
      property :redeem_by
      property :active

      validates :code,          presence: true
      validates :name,          presence: true
      validates :discount_type, inclusion: { in: Billing::Coupon::DISCOUNT_TYPES }
      validates :duration,      inclusion: { in: Billing::Coupon::DURATIONS }

      validates :percent_off,
                numericality: { in: 1..100, only_integer: true },
                if: -> { discount_type == "percent" }

      validates :amount_off_cents,
                numericality: { greater_than: 0, only_integer: true },
                if: -> { discount_type == "fixed" }

      validates :duration_in_cycles,
                numericality: { greater_than: 0, only_integer: true },
                if: -> { duration == "repeating" }

      validates :max_redemptions,
                numericality: { greater_than: 0, only_integer: true }, allow_blank: true
      validate :fixed_currency
      validate :catalog_identity
      validate :valid_expiry

      private

      def fixed_currency
        if discount_type == "fixed" && !%w[USD CNY].include?(currency)
          errors.add(:currency, I18n.t("admin_settings.errors.validations.coupon_fixed_currency"))
        end
      end

      def catalog_identity
        return unless model.is_a?(Billing::Coupon)
        errors.add(:code, :taken) if Billing::Coupon.where(code: code).where.not(id: model.id).exists?
        if model.persisted? && code != model.code
          errors.add(:code, I18n.t("admin_settings.errors.validations.code_immutable"))
        end
      end

      def valid_expiry
        return if redeem_by.blank? || redeem_by.respond_to?(:iso8601)
        errors.add(:redeem_by, :invalid) unless Time.zone.parse(redeem_by.to_s)
      rescue ArgumentError
        errors.add(:redeem_by, :invalid)
      end
    end
  end
end
