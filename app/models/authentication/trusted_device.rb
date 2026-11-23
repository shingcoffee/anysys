# frozen_string_literal: true

module Authentication
  # Server-side record backing the "trust this device" 2FA bypass. The raw
  # token lives only in a signed browser cookie; we persist its SHA-256 digest
  # so a leaked DB row cannot reconstruct a usable cookie. Scoped per
  # (customer_id, user_id) so a token can never satisfy MFA across tenants.
  class TrustedDevice < ApplicationRecord
    self.table_name = "trusted_devices"

    DEFAULT_TTL = 30.days

    belongs_to :user, class_name: "Authentication::User"

    scope :active, -> { where("expires_at > ?", Time.current) }

    # Returns the SHA-256 hex digest of the given raw string.
    def self.digest_for(raw)
      Digest::SHA256.hexdigest(raw.to_s)
    end

    # Returns [record, raw_token]. The raw token is never persisted.
    def self.issue!(user:, ip:, user_agent:, ttl: DEFAULT_TTL)
      raw = SecureRandom.urlsafe_base64(32)
      record = CredentialLifecycle.with_current(user) do |account|
        create!(
          customer_id:  account.customer_id,
          user_id:      account.id,
          token_digest: digest_for(raw),
          expires_at:   ttl.from_now,
          ip:           ip,
          user_agent:   user_agent
        )
      end
      [record, raw]
    end

    # Returns the matching active record for this user, bumping last_used_at;
    # nil if the token is blank, expired, or belongs to another user/tenant.
    def self.authenticate(user:, raw_token:)
      return nil if raw_token.blank? || user.nil?

      record = active.find_by(
        user_id:      user.id,
        customer_id:  user.customer_id,
        token_digest: digest_for(raw_token)
      )
      record&.update_column(:last_used_at, Time.current)
      record
    end
  end
end
