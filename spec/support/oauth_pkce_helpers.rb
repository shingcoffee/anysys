# frozen_string_literal: true

module OauthPkceHelpers
  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [verifier, challenge]
  end

  def oauth_state
    SecureRandom.urlsafe_base64(16)
  end

  def authorize_params(challenge:, state:, redirect_uri:, extra: {})
    {
      client_id: Oauth::Protocol::CLIENT_ID,
      response_type: "code",
      redirect_uri: redirect_uri,
      scope: Oauth::Protocol::SCOPE,
      state: state,
      code_challenge: challenge,
      code_challenge_method: "S256"
    }.merge(extra)
  end

  def extract_redirect_query(location)
    uri = URI.parse(location)
    Rack::Utils.parse_query(uri.query)
  end

  # Authorize used to 302 to the loopback callback. Turbo Drive swallows that
  # cross-origin redirect, so the server now renders an HTML handoff page.
  def oauth_callback_uri
    return response.location if response.redirect?

    uri = Nokogiri::HTML(response.body)
                  .at_css("[data-oauth-native-handoff-url-value]")
                  &.[]("data-oauth-native-handoff-url-value")
    raise "OAuth callback URI missing (status=#{response.status})" if uri.blank?

    uri
  end

  def desktop_access_token_for(user, application: nil)
    app = application || Oauth::DesktopClient.ensure!
    Oauth::AccessToken.create_for(
      application: app,
      resource_owner: user,
      scopes: Oauth::Protocol::SCOPE,
      expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i
    ).plaintext_token
  end
end

RSpec.configure do |config|
  config.include OauthPkceHelpers, type: :request
end
