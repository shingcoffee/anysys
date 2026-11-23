# frozen_string_literal: true

module Sms
  # Vendor-keyed SMS credential row (one per provider × mode). The credential
  # pair (access_key_id / encrypted access_key_secret) is shared across vendors;
  # vendor-specific non-secret config (sign_name, region, from, messaging service
  # SID) lives in the JSON `config` blob so a new vendor needs no schema change.
  class Credential < ApplicationRecord
    self.table_name = "sms_credentials"

    MODES    = %w[sandbox production].freeze
    STATUSES = %w[active disabled].freeze

    encrypts :access_key_secret

    validates :provider, presence: true,
                         inclusion: { in: ->(_) { Sms::Adapters.keys.map(&:to_s) } }
    validates :mode, presence: true, inclusion: { in: MODES },
                     uniqueness: { scope: :provider }
    validates :access_key_id,     presence: true
    validates :access_key_secret, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate  :configured_when_active

    scope :active, -> { where(status: "active") }

    def enabled? = status == "active"

    def adapter_class
      Sms::Adapters.for(provider)
    rescue ArgumentError
      nil
    end

    def configured?
      adapter_class&.configured?(self) || false
    end

    def config_value(key, default = nil)
      (config || {}).fetch(key.to_s, default)
    end

    def write_config(hash)
      self.config = (config || {}).merge(hash.transform_keys(&:to_s))
    end

    private

    # A credential may be saved as a draft, but can only be ACTIVE once the
    # adapter deems it usable — prevents activating an incomplete vendor config.
    def configured_when_active
      return unless status == "active"
      return if configured?

      errors.add(:base, I18n.t("sms.credentials.errors.incomplete"))
    end
  end
end
