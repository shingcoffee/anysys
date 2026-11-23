# frozen_string_literal: true

module Oauth
  # First-party desktop client contract. Values here are the protocol the
  # Windows GUI must follow (see docs/guides/OAUTH_PKCE_DESKTOP.md).
  module Protocol
    CLIENT_ID = "anysys-desktop"
    CLIENT_NAME = "Anysys Desktop"
    SCOPE = "profile"
    CALLBACK_PATH = "/callback"
    MIN_STATE_LENGTH = 16

    # The loopback handoff always navigates with the code in the query string.
    # Doorkeeper's authorization_code flow would also accept fragment and
    # form_post, neither of which can deliver a code to a loopback listener.
    RESPONSE_MODE = "query"

    ACCESS_TOKEN_TTL = 1.hour
    REFRESH_IDLE_TTL = 90.days
    REFRESH_ABSOLUTE_TTL = 1.year
    AUTHORIZATION_CODE_TTL = 10.minutes

    LOOPBACK_REDIRECT_URIS = [
      "http://127.0.0.1#{CALLBACK_PATH}",
      "http://[::1]#{CALLBACK_PATH}"
    ].freeze

    # Host check is delegated to Doorkeeper's URIChecker (IPAddr#loopback?), the
    # same helper the initializer uses to gate redirect_uri registration. It
    # covers the whole 127.0.0.0/8 range and bracketed IPv6, and swallows its
    # own IPAddr errors, so only the scheme/path constraints are ours.
    def self.loopback_redirect?(uri)
      parsed = URI.parse(uri.to_s)
      return false unless parsed.scheme == "http"
      return false unless parsed.path == CALLBACK_PATH

      Doorkeeper::OAuth::Helpers::URIChecker.loopback_uri?(parsed)
    rescue URI::InvalidURIError
      false
    end
  end
end
