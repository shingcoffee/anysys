# frozen_string_literal: true

module Oauth
  # RFC 8414 Authorization Server Metadata for the desktop GUI.
  #
  # Only claims this server actually honours are advertised. Notably absent:
  # `jwks_uri` and `id_token_signing_alg_values_supported` (tokens are opaque,
  # there is no OIDC id_token), and `registration_endpoint` (the single
  # first-party client is seeded by Oauth::DesktopClient, never registered
  # dynamically). `userinfo_endpoint` is an OIDC claim rather than an RFC 8414
  # one, kept because the desktop protocol discovers the endpoint from here.
  class ServerMetadata
    def self.call(request)
      issuer = issuer_from(request)
      {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        revocation_endpoint: "#{issuer}/oauth/revoke",
        userinfo_endpoint: "#{issuer}/oauth/userinfo",
        response_types_supported: %w[code],
        response_modes_supported: [Protocol::RESPONSE_MODE],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: %w[S256],
        token_endpoint_auth_methods_supported: %w[none],
        revocation_endpoint_auth_methods_supported: %w[none],
        scopes_supported: [Protocol::SCOPE],
        ui_locales_supported: I18n.available_locales.map(&:to_s),
        # RFC 9207: Doorkeeper does not add `iss` to the authorization response,
        # so clients must keep relying on `state` for response binding.
        authorization_response_iss_parameter_supported: false
      }
    end

    # When APP_HOST is set (same knob Twilio/Payments webhook URLs use), the
    # issuer is that origin — a spoofed Host header cannot retarget authorize
    # /token onto another site. Without it, fall back to request.base_url and
    # rely on DiscoveryController's Vary: Host so a public cache cannot mix
    # documents from different Hosts.
    def self.issuer_from(request)
      configured = ENV["APP_HOST"].to_s.strip.presence
      return request.base_url unless configured
      return configured.delete_suffix("/") if configured.match?(%r{\Ahttps?://}i)

      base = URI.parse(request.base_url)
      host, port = configured.split(":", 2)
      origin = "#{base.scheme}://#{host}"
      origin += ":#{port}" if port.present?
      origin
    end
    private_class_method :issuer_from
  end
end
