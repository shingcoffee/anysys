# frozen_string_literal: true

module Oauth
  class DiscoveryController < ActionController::API
    # RFC 8414 metadata is public and anonymous. Unlike /oauth/userinfo
    # (no-store) it is cacheable so the desktop client can reuse it across
    # launches. Vary: Host so a shared cache cannot mix issuers.
    CACHE_MAX_AGE = 1.hour

    def show
      expires_in CACHE_MAX_AGE, public: true
      # Issuer URLs follow Host unless APP_HOST is set; caches must not reuse
      # a document minted for a different Host.
      response.set_header("Vary", "Host")
      render json: ServerMetadata.call(request)
    end
  end
end
