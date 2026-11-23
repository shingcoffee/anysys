# frozen_string_literal: true

module Oauth
  # Doorkeeper access tokens with refresh idle/absolute expiry and family
  # revocation on refresh-token reuse (RFC 9700 public-client BCP).
  #
  # A "family" is one refresh chain: the token minted at authorization plus
  # every token rotated out of it. Doorkeeper's RefreshTokenRequest copies
  # `custom_access_token_attributes` (here `family_started_at`) from the old
  # token onto the rotated one, so the whole chain carries the same value and
  # (application_id, resource_owner_id, family_started_at) identifies it.
  # Revocation MUST stay inside that triple — revoking every token for
  # (application_id, resource_owner_id) would let anyone holding one stale
  # refresh token sign the user out of every other device at will.
  class AccessToken < ApplicationRecord
    include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken

    self.table_name = "oauth_access_tokens"

    # `previous_refresh_token` is not in the schema, so Doorkeeper revokes the
    # presented refresh token immediately under a row lock and never treats a
    # revoked token as still-usable. Anything that reaches here already revoked
    # (or past an expiry boundary) is therefore reuse, not a legitimate retry.
    def self.by_refresh_token(refresh_token)
      token = super
      return if token.nil?
      return token unless token.revoked? || token.refresh_expired?

      revoke_family!(token)
      nil
    end

    # Single atomic UPDATE — the previous implementation loaded every row and
    # called #revoke on each, which re-read Doorkeeper config per row.
    def self.revoke_family!(token)
      RefreshTokenConsumption.revoke_family!(token) do
        family_scope(token).where(revoked_at: nil).update_all(revoked_at: Time.now.utc)
      end
    end

    # A NULL family_started_at cannot be attributed to a family (hand-written
    # or pre-family-clock row). Matching on NULL would sweep every other
    # NULL-family session, so such a token revokes only itself.
    def self.family_scope(token)
      return where(id: token.id) if token.family_started_at.blank?

      where(
        application_id: token.application_id,
        resource_owner_id: token.resource_owner_id,
        family_started_at: token.family_started_at
      )
    end
    private_class_method :family_scope

    # Every live token for one resource owner, across all families and
    # applications. This is the credential-change hammer — distinct from
    # .revoke_family!, which must stay narrow (see the class comment). A
    # bearer token skips the cookie session entirely and is exempt from the
    # MFA gate, so a token minted before a password reset or an MFA reset
    # would otherwise outlive the credential it was granted under and keep
    # full admin-API access. Called from Authentication::User.
    def self.revoke_all_for(resource_owner_id)
      where(resource_owner_id: resource_owner_id, revoked_at: nil)
        .update_all(revoked_at: Time.now.utc)
    end

    def self.create_for(application:, resource_owner:, scopes:, **token_attributes)
      token_attributes[:family_started_at] ||= Time.current
      if resource_owner.is_a?(Authentication::User)
        Authentication::CredentialLifecycle.with_current(resource_owner) { super }
      else
        # Doorkeeper supplies an id during exchange; its consumption wrapper
        # must already hold the account lock (see AuthorizationCodeExchange).
        super
      end
    end

    def refresh_expired?
      return true if created_at < Protocol::REFRESH_IDLE_TTL.ago

      started = family_started_at.presence || created_at
      started < Protocol::REFRESH_ABSOLUTE_TTL.ago
    end

    def with_lock(*args, &block)
      RefreshTokenConsumption.call(self) do
        super(*args) do
          # Expiry can cross its boundary between lookup and locked use too.
          raise Doorkeeper::Errors::InvalidGrantReuse if revoked? || refresh_expired?

          block.call
        end
      end
    end
  end
end
