# frozen_string_literal: true

module Oauth
  # AccessToken#with_lock is Doorkeeper's refresh-consumption boundary. Catch
  # locked reuse outside its savepoint, so the rejection cannot roll back the
  # family revocation. Unrelated errors must not revoke an innocent family.
  class RefreshTokenConsumption
    def self.call(token)
      user = Authentication::User.find_by(id: token.resource_owner_id)
      unless user
        raise Doorkeeper::Errors::InvalidGrant.new(
          Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)
        )
      end

      user.with_lock(requires_new: true) { yield }
    rescue Doorkeeper::Errors::InvalidGrantReuse
      token.class.revoke_family!(token)
      raise
    end

    # Serialize sequential lookup-time reuse with rotation too: an UPDATE
    # racing a rotation could otherwise miss the newly inserted descendant.
    def self.revoke_family!(token)
      user = Authentication::User.find_by(id: token.resource_owner_id)
      user ? user.with_lock(requires_new: true) { yield } : yield
    end
  end
end
