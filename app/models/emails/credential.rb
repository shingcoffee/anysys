# frozen_string_literal: true

require "openssl"
require "base64"

module Emails
  # Vendor-keyed email credential (one per provider × mode). SMTP (the standard
  # protocol) keeps its typed columns (host/port/username/auth/ssl/starttls/
  # domain/dkim_*); API vendors (SES, Aliyun, …) store their config in the JSON
  # `config` blob. The encrypted `password` column holds the SMTP password or the
  # API token; `dkim_private_key` stays encrypted for SMTP DKIM signing.
  class Credential < ApplicationRecord
    self.table_name = "email_credentials"

    MODES = %w[sandbox production].freeze
    STATUSES = %w[active disabled].freeze
    AUTHENTICATIONS = %w[plain login cram_md5].freeze

    encrypts :password
    encrypts :dkim_private_key
    # Webhook signing secret (e.g. Aliyun Basic-Auth password) — a secret, so
    # it lives in an encrypted column, never the plaintext config blob.
    encrypts :webhook_secret

    validates :provider, presence: true,
                         inclusion: { in: ->(_) { Email::Providers.keys.map(&:to_s) } }
    validates :mode, presence: true, inclusion: { in: MODES }, uniqueness: { scope: :provider }
    validates :password, presence: true
    validates :status, inclusion: { in: STATUSES }
    # SMTP-specific typed fields — only required for the SMTP provider (API
    # providers leave host/username null and use the config blob).
    with_options if: :smtp? do
      validates :host, presence: true
      validates :port, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
      validates :username, presence: true
      validates :authentication, inclusion: { in: AUTHENTICATIONS }
      validates :dkim_domain,      presence: true, if: :dkim_enabled
      validates :dkim_selector,    presence: true, if: :dkim_enabled
      validates :dkim_private_key, presence: true, if: :dkim_enabled
    end
    validate :configured_when_active

    scope :active, -> { where(status: "active") }

    def enabled? = status == "active"
    def smtp?    = provider.to_s == "smtp"

    def tracking_enabled?
      config_value(:tracking_enabled, true).to_s != "false"
    end

    def provider_class
      Email::Providers.for(provider)
    rescue ArgumentError
      nil
    end

    def configured?
      provider_class&.configured?(self) || false
    end

    def config_value(key, default = nil)
      (config || {}).fetch(key.to_s, default)
    end

    def write_config(hash)
      self.config = (config || {}).merge(hash.transform_keys(&:to_s))
    end

    # The envelope From address: SMTP uses the auth username; API vendors use a
    # configured from_email.
    def from_address
      smtp? ? username : config_value(:from_email)
    end

    def dkim_configured?
      smtp? && dkim_enabled && dkim_domain.present? && dkim_selector.present? && dkim_private_key.present?
    end

    # DNS TXT record for the selector, derived from the stored private key.
    def dkim_dns_txt_record
      return nil unless dkim_configured?

      public_der = OpenSSL::PKey::RSA.new(dkim_private_key).public_key.to_der
      %(#{dkim_selector}._domainkey.#{dkim_domain}  TXT  "v=DKIM1; k=rsa; p=#{Base64.strict_encode64(public_der)}")
    rescue OpenSSL::PKey::PKeyError
      nil
    end

    private

    def configured_when_active
      return unless status == "active"
      return if configured?

      errors.add(:base, I18n.t("email.credentials.errors.incomplete"))
    end
  end
end
