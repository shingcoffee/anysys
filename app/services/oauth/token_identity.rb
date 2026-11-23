# frozen_string_literal: true

module Oauth
  # The single place a Bearer access token is turned into a usable user.
  # Both Oauth::BearerAuthenticatable (tenant-scoped admin JSON APIs) and
  # Oauth::UserinfoController resolve identity through here so the two paths
  # cannot drift apart on what makes a token acceptable:
  #
  #   * live (not expired, not revoked) and carrying the `profile` scope;
  #   * issued to the first-party desktop client, not some other application;
  #   * owned by an active, confirmed and unlocked account (Devise eligibility).
  class TokenIdentity
    def self.call(token)
      new(token).call
    end

    def initialize(token)
      @token = token
    end

    # @return [Authentication::User, nil] nil whenever the caller must answer 401
    def call
      return unless first_party_desktop_token?

      user = Authentication::User.find_by(id: @token.resource_owner_id)
      user if user&.active_for_authentication?
    end

    private

    def first_party_desktop_token?
      @token&.acceptable?([Protocol::SCOPE]) && @token.application&.uid == Protocol::CLIENT_ID
    end
  end
end
