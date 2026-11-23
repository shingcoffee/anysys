# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    layout "auth"

    before_action :require_desktop_authorize_params!, only: %i[new create destroy]
    before_action :validate_denial_request!, only: :destroy

    private

    # Doorkeeper's resource_owner_authenticator delegates here so the
    # initializer holds no routing knowledge. It reaches this method through
    # instance_eval, so it does not need to be public (and must not be — every
    # public controller method is a candidate action).
    def authenticate_desktop_resource_owner!
      result = AuthenticateResourceOwner.call(
        user: current_user,
        mfa_verified: mfa_session_verified?
      )
      return result.user if result.authorized?

      store_location_for(:user, request.fullpath)
      redirect_to resource_owner_redirect_path(result)
    end

    def resource_owner_redirect_path(result)
      case result.next_action
      when :mfa_verify then mfa_session_path(result.user.customer_id)
      when :mfa_setup  then mfa_setup_path(result.user.customer_id)
      else new_user_session_path
      end
    end

    # `state` is the desktop client's only CSRF/response binding, and the code
    # can only reach a loopback listener through the query string — so pin both
    # to what /.well-known advertises rather than accepting Doorkeeper's wider
    # defaults. Renders the OAuth error page (not a redirect): without a
    # trustworthy `state` there is nothing safe to redirect back to.
    def require_desktop_authorize_params!
      render_invalid_request unless desktop_state? && desktop_response_mode?
    end

    def desktop_state?
      params[:state].to_s.length >= Protocol::MIN_STATE_LENGTH
    end

    def desktop_response_mode?
      params[:response_mode].blank? || params[:response_mode] == Protocol::RESPONSE_MODE
    end

    def render_invalid_request
      render :error, locals: {
        error_response: Doorkeeper::OAuth::ErrorResponse.new(
          name: :invalid_request,
          state: params[:state]
        )
      }, status: :bad_request
    end

    # Doorkeeper's #destroy calls #deny without validating pre_auth, then
    # redirects to its supplied redirect_uri. Validate the client and its
    # registered destination first; invalid requests stay on the error page.
    def validate_denial_request!
      return if pre_auth.authorizable?

      error_response = pre_auth.error_response
      render :error, locals: { error_response: error_response }, status: error_response.status
    end

    # `family_started_at` is the refresh-family clock and must be issued by the
    # server (Oauth::AccessToken.create_for). Doorkeeper otherwise reads every
    # configured custom access token attribute straight out of the authorize
    # query string and writes it to the access grant — which has no such
    # column — so a client could both crash the endpoint and pick its own
    # absolute refresh deadline.
    def pre_auth_param_fields
      super - custom_access_token_attributes
    end

    def authorize_response
      # Grant issuance must use the same account lock as credential revocation,
      # otherwise a request holding an old session snapshot can insert its
      # grant just after revocation has scanned the outstanding codes.
      @authorize_response ||= Authentication::CredentialLifecycle.with_current(current_resource_owner) { super }
    end

    # Turbo Drive swallows a 302 to 127.0.0.1 (cross-origin from the app host),
    # which is how the GUI receives the authorization code. Render an HTML
    # handoff page instead so the browser navigates to the loopback callback.
    def redirect_or_render(auth)
      if auth.redirectable? && Protocol.loopback_redirect?(auth.redirect_uri)
        request.format = :html
        protect_authorization_code!
        render template: "oauth/authorizations/native_handoff",
               formats: [:html],
               locals: { redirect_uri: auth.redirect_uri }
      else
        super
      end
    end

    # The rendered page embeds a URL carrying the authorization code. Keep it
    # out of shared caches, and out of the Referer header the browser would
    # otherwise attach when it follows the meta refresh or the continue link.
    def protect_authorization_code!
      response.headers["Cache-Control"] = "no-store"
      response.headers["Pragma"] = "no-cache"
      response.headers["Referrer-Policy"] = "no-referrer"
    end
  end
end
