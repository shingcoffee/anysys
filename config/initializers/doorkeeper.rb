# frozen_string_literal: true

# Doorkeeper is configured before Zeitwerk can autoload, and the token
# lifetimes below have to be read at configure time. Oauth::Protocol is a
# constants-only module with no app dependencies, so requiring it here is safe
# (Zeitwerk tracks the explicit require and still reloads the file in
# development).
require Rails.root.join("app/services/oauth/protocol")

Doorkeeper.configure do
  orm :active_record

  access_token_class "Oauth::AccessToken"

  # Evaluated in the Doorkeeper controller instance. Oauth::AuthorizationsController
  # owns both the decision (Oauth::AuthenticateResourceOwner) and the
  # next_action -> path mapping, so no routing knowledge lives here.
  resource_owner_authenticator do
    authenticate_desktop_resource_owner!
  end

  skip_authorization do |_resource_owner, client|
    client.uid == Oauth::Protocol::CLIENT_ID
  end

  after_successful_authorization do |controller, _context|
    next unless controller.is_a?(Oauth::AuthorizationsController)

    Authentication::AuditLog.record(
      event: :oauth_authorized,
      user: controller.current_user,
      request: controller.request,
      client_id: controller.params[:client_id]
    )
  end

  base_controller "ApplicationController"

  grant_flows %w[authorization_code]
  default_scopes :profile
  enforce_configured_scopes
  force_pkce
  pkce_code_challenge_methods %w[S256]
  use_refresh_token
  hash_token_secrets
  hash_application_secrets

  # Single source of truth: Oauth::Protocol is what docs/guides/OAUTH_PKCE_DESKTOP.md
  # documents to the desktop client, and Oauth::AccessToken#refresh_expired?
  # reads the refresh lifetimes from the same place.
  authorization_code_expires_in Oauth::Protocol::AUTHORIZATION_CODE_TTL
  access_token_expires_in Oauth::Protocol::ACCESS_TOKEN_TTL

  custom_access_token_attributes [:family_started_at]

  force_ssl_in_redirect_uri do |uri|
    !Doorkeeper::OAuth::Helpers::URIChecker.loopback_uri?(uri)
  end

  forbid_redirect_uri do |uri|
    next true unless uri.is_a?(URI) && uri.host.present?

    !Doorkeeper::OAuth::Helpers::URIChecker.loopback_uri?(uri)
  end

  allow_grant_flow_for_client do |grant_flow, client|
    client.uid == Oauth::Protocol::CLIENT_ID &&
      %w[authorization_code refresh_token].include?(grant_flow)
  end
end
