# frozen_string_literal: true

module Oauth
  # Opt-in Bearer authentication for first-party desktop API controllers.
  # Cookie sessions are not accepted — the client must send Authorization.
  #
  # This runs as a *prepended* filter, so it is the first thing in the chain.
  # Everything ApplicationController normally does still runs afterwards, which
  # is what keeps a bearer request tenant-safe: TenantContext#auto_set_tenant_from_path
  # sees the user signed in by this filter and rejects a `/:cid/...` URL whose
  # customer is not the token owner's (unless they are the platform owner), and
  # RouteAuthorization then applies the usual admin/member role gate.
  module BearerAuthenticatable
    extend ActiveSupport::Concern

    included do
      prepend_before_action :authenticate_oauth_bearer!
      skip_forgery_protection
      skip_before_action :enforce_mfa!, raise: false
    end

    private

    def authenticate_oauth_bearer!
      request.format = :json

      user = TokenIdentity.call(Doorkeeper.authenticate(request))
      unless user
        render json: { error: "invalid_token" }, status: :unauthorized
        return
      end

      # TokenIdentity explicitly applies Devise's account-eligibility predicate.
      # Establish only this request's principal: callbacks would otherwise run
      # Trackable/Rememberable effects on every stateless API request.
      warden.set_user(user, scope: :user, store: false, run_callbacks: false)
    end

    # Rails 8.1 turns `allow_browser versions: :modern` into an *anonymous*
    # lambda before_action (ActionController::AllowBrowser::ClassMethods#allow_browser)
    # whose only job is to call this private instance method. An anonymous
    # lambda filter cannot be named in skip_before_action, and the filter is
    # declared on ApplicationController, so overriding the method it calls is
    # the only seam available for opting a non-browser JSON API out of the
    # 406 check. spec/requests/oauth/bearer_authenticatable_spec.rb pins the
    # seam so a Rails upgrade that renames or drops it fails loudly instead of
    # silently 406-ing every desktop client.
    def allow_browser(versions:, block:)
    end
  end
end
