# frozen_string_literal: true

module Payments
  # Vaulted card record. Stores PSP tokens + display metadata only.
  # NEVER stores PAN, CVV, or any raw card data. The card is captured
  # exclusively inside the Stripe-hosted Payment/SetupIntent Element
  # (PCI SAQ-A posture).
  class PaymentMethod < ApplicationRecord
    include TenantScoped

    self.table_name = "payment_methods"

    STATUSES = %w[active expired removed].freeze

    # Stripe PaymentMethod.card.brand values. Unknown brands render as the raw key.
    BRANDS = %w[
      amex cartes_bancaires diners discover eftpos_au jcb link mastercard unionpay unknown visa
    ].freeze

    # A freshly-vaulted card holds a placeholder token until the PSP's
    # setup_intent.succeeded webhook backfills the real token + card metadata.
    # Such a row is NOT chargeable and must not be handed to an off-session charge.
    PENDING_TOKEN_PREFIX = "pending:"

    validates :customer_id,           presence: true
    validates :user_id, presence: true, unless: :billing_token?
    validates :billing_customer_id, :billing_authorized_by_id, presence: true, if: :billing_token?
    validate :vault_ownership
    validates :provider,              presence: true,
                                      inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }
    validates :psp_payment_method_id, presence: true
    validates :status,                inclusion: { in: STATUSES }

    scope :active,    -> { where(status: "active") }
    scope :for_user,  ->(uid) { where(user_id: uid) }
    scope :confirmed, -> { where.not("psp_payment_method_id LIKE ?", "#{PENDING_TOKEN_PREFIX}%") }
    scope :pending,    -> { where("psp_payment_method_id LIKE ?", "#{PENDING_TOKEN_PREFIX}%") }
    scope :chargeable, -> { active.confirmed }
    # Billing vault tokens live on the platform customer and belong to another
    # tenant's invoice mandate. Commerce subscription setup must not offer them.
    scope :commerce, -> { where(billing_customer_id: nil) }

    # True when the card is confirmed by the PSP (real token, not a placeholder).
    def confirmed? = !psp_payment_method_id.to_s.start_with?(PENDING_TOKEN_PREFIX)

    # True when this vaulted card can back an off-session charge right now.
    def chargeable? = status == "active" && confirmed?

    def billing_token? = billing_customer_id.present?

    # Returns a human-readable card label, e.g. "Visa •••• 4242".
    def display_label
      parts = [brand_label.presence, "•••• #{last4}"].compact
      parts.join(" ")
    end

    def brand_label
      key = brand.to_s
      return if key.blank?

      if BRANDS.include?(key)
        I18n.t("comp_payments.payment_method.brands.#{key}")
      else
        key
      end
    end

    # Soft-removes the vaulted card. Caller is responsible for calling
    # gateway#detach_token before or after to revoke the PSP token.
    def mark_removed!
      update!(status: "removed", is_default: false)
    end

    private

    def vault_ownership
      if billing_token?
        errors.add(:base, :invalid) unless customer_id == Authentication::User::PLATFORM_CUSTOMER_ID && user_id.nil?
      else
        errors.add(:base, :invalid) if billing_authorized_by_id.present?
      end
    end
  end
end
