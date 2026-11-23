# frozen_string_literal: true

module Oauth
  # RFC 7009 revoke must be a no-op 200 for an already-revoked refresh token.
  # Doorkeeper's stock lookup uses AccessToken.by_refresh_token, which is our
  # RFC 9700 reuse detector and would family-revoke the live session.
  class TokensController < Doorkeeper::TokensController
    private

    def authorize_response
      return super unless params[:grant_type] == "authorization_code"

      # Doorkeeper reads this response for headers, body and status. Cache the
      # whole locked exchange so later reads do not try to consume the code again.
      @authorize_response ||= Oauth::AuthorizationCodeExchange.call(code: params[:code]) { super }
    end

    def refresh_token
      token = Oauth::AccessToken.find_by_plaintext_token(:refresh_token, params["token"])
      return unless token

      Doorkeeper::RevocableTokens::RevocableRefreshToken.new(token)
    end
  end
end
