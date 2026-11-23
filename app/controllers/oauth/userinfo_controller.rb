# frozen_string_literal: true

module Oauth
  class UserinfoController < ActionController::API
    include Doorkeeper::Rails::Helpers

    before_action :forbid_caching
    before_action -> { doorkeeper_authorize!(Protocol::SCOPE) }
    before_action :resolve_desktop_user!

    def show
      render json: Userinfo.call(@user)
    end

    private

    # This is a per-user identity document handed out against a bearer token
    # (RFC 6749 §5.1) — no intermediary may keep a copy. Contrast with
    # Oauth::DiscoveryController, whose body is public and identical for every
    # caller and so is deliberately cacheable.
    def forbid_caching
      response.headers["Cache-Control"] = "no-store"
      response.headers["Pragma"] = "no-cache"
    end

    # Client identity, liveness and owner checks all live in Oauth::TokenIdentity,
    # shared with Oauth::BearerAuthenticatable. doorkeeper_authorize! above has
    # already produced the RFC 6750 response for a missing/expired token or a
    # token without `profile`; what is left is a live token belonging to some
    # other OAuth application, or to a user who is gone or deactivated.
    def resolve_desktop_user!
      @user = TokenIdentity.call(doorkeeper_token)
      return if @user

      render json: { error: "invalid_token" }, status: :unauthorized
    end

    def doorkeeper_unauthorized_render_options(**)
      { json: { error: "invalid_token" } }
    end

    def doorkeeper_forbidden_render_options(**)
      { json: { error: "insufficient_scope" } }
    end
  end
end
