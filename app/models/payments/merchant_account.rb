# frozen_string_literal: true

module Payments
  # Per-(customer, provider, mode) credential row. Customer-selectable: setting
  # `status = "active"` is what marks a gateway as enabled for the tenant. The
  # checkout flow filters by status: "active", so toggling this off is also
  # how the customer disables a gateway without losing its credentials.
  #
  # Vendor-specific credential fields live in the encrypted `credentials` JSON
  # blob — what each gateway needs is declared by its
  # Payments::Gateways::<Vendor>.credential_fields list.
  class MerchantAccount < ApplicationRecord
    include JsonSerializable
    include TenantScoped

    self.table_name = "payment_merchant_accounts"

    encrypts :credentials
    json_attribute :credentials, default: {}

    MODES    = %w[sandbox production].freeze
    STATUSES = %w[active disabled].freeze

    validates :provider,    presence: true,
                            inclusion: { in: ->(_) { Payments::Gateways.keys.map(&:to_s) } }
    validates :mode,        presence: true, inclusion: { in: MODES }
    validates :merchant_id, presence: true
    validates :status,      inclusion: { in: STATUSES }
    validates :customer_id, presence: true
    validates :mode, uniqueness: { scope: %i[customer_id provider] }
    # Matches idx_payment_accounts_on_prov_mch. Without this, assigning another
    # tenant's (or the sibling sandbox/production row's) merchant_id raises
    # RecordNotUnique and 500s the Settings save instead of a 422.
    validates :merchant_id, uniqueness: { scope: :provider }

    scope :active, -> { where(status: "active") }

    def enabled? = status == "active"

    # A gateway is "configured" when it is enabled, has a real (non-placeholder)
    # merchant_id, and every credential field declared by its gateway class has a
    # stored value. Used to decide default-gateway / checkout eligibility.
    def configured?
      return false unless enabled?
      return false if merchant_id.blank? || merchant_id.to_s.start_with?("unset-")

      gateway_class.credential_fields.all? { |f| credential(f[:name]).present? }
    rescue ArgumentError
      false
    end

    def gateway_class
      Payments::Gateways.for(provider)
    end

    # Per-merchant default currency shown in the Settings UI. Stored in the
    # encrypted credentials blob (NOT a typed column — AGENTS.md forbids typed
    # columns on payment_merchant_accounts), falling back to the gateway's first
    # supported currency.
    def default_currency
      credential(:default_currency).presence ||
        (gateway_class.supported_currencies.first rescue "cny")
    end

    # Read a vendor-specific credential out of the encrypted JSON blob.
    def credential(key)
      credentials_json[key.to_s]
    end

    # Replace one or more vendor-specific credentials, merging into whatever
    # is already stored. Pass nil/empty to keep the existing value (used by the
    # form so blank submissions don't clobber encrypted secrets).
    def write_credentials(hash)
      merged = credentials_json.merge(hash.transform_keys(&:to_s)) do |_, old, new_val|
        new_val.nil? || (new_val.respond_to?(:empty?) && new_val.empty?) ? old : new_val
      end
      self.credentials_json = merged
    end
  end
end
