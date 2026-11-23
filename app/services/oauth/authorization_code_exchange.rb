# frozen_string_literal: true

module Oauth
  # Controller integration: wrap the authorization-code strategy in .call.
  # Lock the user BEFORE Doorkeeper locks the grant, matching credential
  # revocation's user -> grant order and rechecking any stale grant lookup.
  class AuthorizationCodeExchange
    def self.call(code:)
      grant = Doorkeeper.config.access_grant_model.by_token(code)
      return yield unless grant

      user = Authentication::User.find_by(id: grant.resource_owner_id)
      invalid_grant! unless user

      user.with_lock(requires_new: true) do
        invalid_grant! unless grant.reload.accessible?

        yield
      end
    end

    def self.invalid_grant!
      raise Doorkeeper::Errors::InvalidGrant.new(
        Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)
      )
    end
    private_class_method :invalid_grant!
  end
end
