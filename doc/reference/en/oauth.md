---
title: "OAuth"
summary: "How the first-party desktop client obtains a PKCE authorization code, refreshes it, and calls the app with a bearer token."
---

## Summary

This app is an OAuth 2.0 authorization server for one public client, `anysys-desktop`. Doorkeeper issues authorization codes and opaque tokens. PKCE S256 is required. The browser sign-in is the same Devise session as [Authentication](authentication), including MFA, and there is no separate consent screen for this client. API calls send `Authorization: Bearer` and do not reuse the cookie session.

The desktop protocol notes in `docs/guides/OAUTH_PKCE_DESKTOP.md` match the constants in `Oauth::Protocol`. When they disagree with the code, the code wins.

## Flow

```text
GET /.well-known/oauth-authorization-server
        |
        v
Oauth::DiscoveryController -> Oauth::ServerMetadata
        |
        v
GET /oauth/authorize
  client_id=anysys-desktop
  code_challenge S256, state length >= 16, response_mode query or omitted
  redirect_uri http://127.0.0.1:<port>/callback or http://[::1]/callback
        |
        v
Oauth::AuthorizationsController#authenticate_desktop_resource_owner!
        |
        v
Oauth::AuthenticateResourceOwner
        |  :sign_in    -> /auth/sign_in   (return stored)
        |  :mfa_verify -> /:cid/auth/mfa/session
        |  :mfa_setup  -> /:cid/auth/mfa/setup
        |  :authorized -> Doorkeeper issues the code
        v
HTML handoff (not a 302) -> loopback ?code=&state=
        |
        v
POST /oauth/token
  authorization_code + code_verifier    or    refresh_token
        |
        v
Oauth::AccessToken   (hashed secret, family_started_at)
        |
        +--> GET /oauth/userinfo                          Oauth::Userinfo
        |
        +--> Bearer API (cookie rejected, MFA filter skipped)
               GET  /:cid/admin/entity_definitions
               /:cid/admin/assistant/messages
               /:cid/admin/assistant/transcriptions
               |
               Oauth::BearerAuthenticatable
               Oauth::TokenIdentity
                warden.set_user(user, store: false, run_callbacks: false)
               TenantContext + RouteAuthorization still run
```

`POST /oauth/revoke` revokes the refresh token that was presented. Reuse of an already revoked or idle-expired refresh token, on the refresh grant, revokes the whole family.

## Implementation

### Configuration

`config/initializers/doorkeeper.rb` loads `Oauth::Protocol` and sets:

- `access_token_class` `"Oauth::AccessToken"`
- `grant_flows` `authorization_code` only. `allow_grant_flow_for_client` also allows `refresh_token`, and only when `client.uid` is `Oauth::Protocol::CLIENT_ID`.
- `force_pkce` and `pkce_code_challenge_methods` `%w[S256]`
- `use_refresh_token`
- `hash_token_secrets` and `hash_application_secrets`
- `default_scopes` `:profile`, `enforce_configured_scopes`
- lifetimes from `Oauth::Protocol`: authorization code `10.minutes`, access token `1.hour`
- `custom_access_token_attributes [:family_started_at]`
- `skip_authorization` when the client uid is `anysys-desktop`
- `resource_owner_authenticator` calls `authenticate_desktop_resource_owner!` on the controller
- `base_controller` `"ApplicationController"`
- redirect URIs must be loopback (`force_ssl_in_redirect_uri` is false only for loopback, and `forbid_redirect_uri` rejects every non-loopback URI)

`use_doorkeeper` in `config/routes.rb` skips `:applications`, `:authorized_applications`, and `:token_info`, and points authorizations at `oauth/authorizations` and tokens at `oauth/tokens`. Doorkeeper's route mapper then draws, under the `oauth` scope, `GET /oauth/authorize` (`new`), `POST /oauth/authorize` (`create`), `DELETE /oauth/authorize` (`destroy`), `GET /oauth/authorize/native` (the gem's native-code path; this app's loopback success path renders the handoff page instead), `POST /oauth/token`, and `POST /oauth/revoke`. The mapper also draws `POST /oauth/introspect` when `allow_token_introspection` is not `false`. This initializer does not set that option. The installed Doorkeeper 5.9 default is a lambda, so the introspect route is mounted. `Oauth::ServerMetadata` does not advertise introspect or the native path.

`GET /.well-known/oauth-authorization-server` is `Oauth::DiscoveryController#show`. `GET /oauth/userinfo` is `Oauth::UserinfoController#show`.

### Client

`Oauth::Protocol` is the contract: `CLIENT_ID` `"anysys-desktop"`, `SCOPE` `"profile"`, `CALLBACK_PATH` `"/callback"`, `MIN_STATE_LENGTH` `16`, `RESPONSE_MODE` `"query"`. `LOOPBACK_REDIRECT_URIS` lists `http://127.0.0.1/callback` and `http://[::1]/callback` without a port. `loopback_redirect?` accepts any loopback host Doorkeeper's `URIChecker.loopback_uri?` accepts, scheme `http`, path exactly `/callback`. An ephemeral port on `127.0.0.1` therefore matches the predicate even though it is not one of the two seed strings.

`Oauth::DesktopClient.ensure!` finds or creates the `Doorkeeper::Application` with that uid, sets the name, the two redirect URIs joined by newlines, `confidential: false`, and scopes `profile`. It does not rotate an existing hashed secret. `config/initializers/oauth_desktop_client.rb` calls `ensure!` after initialize outside the test environment, when `oauth_applications` exists. `db/seeds.rb` calls it too.

### Authorize

`Oauth::AuthorizationsController` uses the `auth` layout. `require_desktop_authorize_params!` on `new`, `create` and `destroy` returns a local `400 invalid_request` unless state has at least 16 characters and response mode is blank or `query`. Denial checks `pre_auth.authorizable?` before redirecting; unknown clients, disallowed flows and unregistered/malformed destinations remain local errors.

`authenticate_desktop_resource_owner!` calls `Oauth::AuthenticateResourceOwner` with `current_user` and `mfa_session_verified?`. The service returns `:sign_in` when the user is missing, inactive, or the authentication module is disabled for their customer. It returns `:mfa_verify` or `:mfa_setup` from `Authentication::MfaObligation`, and `:authorized` otherwise. The controller stores `request.fullpath` with Devise and redirects to the sign-in form or to `mfa_session_path` / `mfa_setup_path` for `result.user.customer_id`. `oauth/authorizations` is on `Authentication::EnforcesMfa`'s challenge exemption list so this redirect is not itself redirected. The obligation is asked again here, so authorize cannot skip an outstanding second factor.

`pre_auth_param_fields` removes `family_started_at` from the authorize query. `Oauth::AccessToken.create_for` sets `family_started_at` to `Time.current` when the caller did not pass one. Doorkeeper copies that attribute onto later refreshes.

`redirect_or_render` detects a loopback `redirect_uri` and renders `oauth/authorizations/native_handoff` instead of letting Doorkeeper send a 302. Turbo would drop a cross-origin redirect to `127.0.0.1`. `protect_authorization_code!` sets `Cache-Control: no-store`, `Pragma: no-cache`, and `Referrer-Policy: no-referrer`. A successful authorization audits `:oauth_authorized` from the initializer's `after_successful_authorization` hook.

PKCE itself is Doorkeeper's, turned on by `force_pkce` and the S256 method list. The token request must send `code_verifier`. This app does not reimplement the S256 comparison.

### Tokens, refresh, revocation

`Oauth::AccessToken` uses `oauth_access_tokens` and Doorkeeper's ActiveRecord mixin. Secrets are hashed because `hash_token_secrets` is on. `refresh_expired?` is true when `created_at` is older than `Protocol::REFRESH_IDLE_TTL` (90 days) or when `family_started_at` (or `created_at` if the family clock is blank) is older than `Protocol::REFRESH_ABSOLUTE_TTL` (1 year).

`by_refresh_token` returns the row when it is live. A revoked or refresh-expired row calls `revoke_family!` and returns nil, which is the RFC 9700 reuse response. `revoke_family!` sets `revoked_at` on every unrevoked row with the same `application_id`, `resource_owner_id`, and `family_started_at`. A blank `family_started_at` revokes only that row, so a NULL family cannot sign out every other NULL-family session.

`Oauth::TokensController#refresh_token` is only the RFC 7009 revoke lookup. It uses `find_by_plaintext_token(:refresh_token, params["token"])` and wraps the row in `Doorkeeper::RevocableTokens::RevocableRefreshToken`. It does not call `by_refresh_token`, so revoking an already-revoked refresh token stays a no-op `200` and does not family-revoke the live chain.

`revoke_all_for` revokes every live token for a resource owner across families/applications. `Authentication::CredentialLifecycle` calls it transactionally on password, existing-secret, email or customer-identity changes and also revokes outstanding grants. This is separate from family reuse.

Expired/revoked authorization codes and missing account lookups return structured `400 invalid_grant` responses without issuing a token. The installed Doorkeeper `InvalidGrant` is a `BaseResponseError` and requires the response object in its constructor; exchange and refresh guards use `Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)`. An unredeemed code revoked by a credential change follows that same error contract.

```ruby
raise Doorkeeper::Errors::InvalidGrant.new(
  Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)
)
```

### Userinfo and bearer APIs

`Oauth::UserinfoController` is an API controller with no-store responses and profile-scope authorization. `TokenIdentity` requires an acceptable first-party desktop token and `user.active_for_authentication?`, explicitly rejecting inactive, unconfirmed or locked accounts. Invalid identity returns `401 invalid_token`; insufficient scope returns `403 insufficient_scope`. Userinfo returns sub/email/email_verified/name/customer_id/role.

`Oauth::BearerAuthenticatable` prepends token authentication on entity definitions and desktop assistant/message/transcription controllers. It forces JSON and calls `warden.set_user(user, scope: :user, store: false, run_callbacks: false)` after TokenIdentity checks. Trackable/Rememberable callbacks do not run; browser history and session cookies are untouched. Cookie-only requests remain invalid. Bearer actions skip cookie CSRF/MFA and the modern-browser gate, while tenant/admin authorization still runs.

Because the controller still inherits `ApplicationController`, `TenantContext` and `RouteAuthorization` run after the bearer sign-in. A `/:cid/admin/...` URL whose customer is not the token owner's is rejected unless `platform_owner?`. The admin role gate and `authorize_route!` still apply. The cookie is not consulted: `store: false` and the filter always requires a bearer token.

`Oauth::ServerMetadata` publishes `issuer`, `authorization_endpoint`, `token_endpoint`, `revocation_endpoint`, `userinfo_endpoint`, response type `code`, response mode `query`, grant types `authorization_code` and `refresh_token`, S256, token and revocation auth method `none`, scope `profile`, the available locales, and `authorization_response_iss_parameter_supported: false`. When `ENV["APP_HOST"]` is set, the issuer is that origin. Otherwise the issuer is `request.base_url`, and the discovery response sets `Vary: Host` and `Cache-Control: public, max-age=3600`.

## Where to pay attention

### Route audit: issuance, exchange and refresh invariants

Issuance uses `CredentialLifecycle.with_current(current_resource_owner)`. Authorization-code responses use `Oauth::AuthorizationCodeExchange.call(code:)`; refresh consumption uses `Oauth::RefreshTokenConsumption`. Each takes the user lock before grant/token locks and checks persisted state. Reuse revocation runs outside the failed consumption savepoint, so `invalid_grant` cannot undo it. Doorkeeper still owns client/PKCE checks and RFC 7009 no-op revocation.

Native GET displays the supplied code; introspection is mounted with gem authorization but unadvertised in discovery. The callback-free bearer principal preserves browser tracking while explicit Devise eligibility supplies the account check. See [Authentication](authentication) and [Tenancy and roles](tenancy-and-roles).

:::note
PKCE, exchange/refresh and callback-free bearer APIs are source-documented. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Browser and lock-contention evidence beyond that suite remain separate.
:::

:::attention
`Oauth::AccessToken.revoke_family!` covers one `(application_id, resource_owner_id, family_started_at)` triple. `CredentialLifecycle` uses `revoke_all_for` for credential changes; family-only revocation would leave other desktop sessions signed in.
:::

:::attention
`Oauth::TokensController#refresh_token` looks up the revoke target with `find_by_plaintext_token`. `by_refresh_token` is the reuse detector and family-revokes. The revoke action must not go through that lookup.
:::

:::attention
`Oauth::AuthorizationsController#pre_auth_param_fields` drops `family_started_at`. `Oauth::AccessToken.create_for` assigns the clock on the server. A client value in the authorize query is discarded before Doorkeeper writes the grant.
:::

:::attention
`Oauth::BearerAuthenticatable` skips `Authentication::EnforcesMfa`. The second factor is required in `Oauth::AuthenticateResourceOwner` at `GET /oauth/authorize`, which uses `Authentication::MfaObligation`. A bearer token issued before MFA was turned on keeps working until it is revoked, expires, or fails `refresh_expired?`.
:::

:::note
`Oauth::UserinfoController` does not include `TenantContext`. It identifies the user from the token alone. Tenant checks start on the admin bearer controllers, which include `Oauth::BearerAuthenticatable` and inherit `ApplicationController`.
:::

## Key code

```ruby
# config/initializers/doorkeeper.rb
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
```

```ruby
# app/services/oauth/protocol.rb
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
```

```ruby
# app/models/oauth/access_token.rb
    def self.by_refresh_token(refresh_token)
      token = super
      return if token.nil?
      return token unless token.revoked? || token.refresh_expired?

      revoke_family!(token)
      nil
    end
```

```ruby
# app/controllers/oauth/tokens_controller.rb
    def refresh_token
      token = Oauth::AccessToken.find_by_plaintext_token(:refresh_token, params["token"])
      return unless token

      Doorkeeper::RevocableTokens::RevocableRefreshToken.new(token)
    end
```

```ruby
# app/controllers/concerns/oauth/bearer_authenticatable.rb
    def authenticate_oauth_bearer!
      request.format = :json

      user = TokenIdentity.call(Doorkeeper.authenticate(request))
      unless user
        render json: { error: "invalid_token" }, status: :unauthorized
        return
      end

      # TokenIdentity performs account eligibility; suppress browser callbacks.
      warden.set_user(user, scope: :user, store: false, run_callbacks: false)
    end
```

```ruby
# app/services/oauth/authenticate_resource_owner.rb
    def pending_mfa_action
      case Authentication::MfaObligation.for(user: @user, verified: @mfa_verified)
      when Authentication::MfaObligation::VERIFY then :mfa_verify
      when Authentication::MfaObligation::ENROLL then :mfa_setup
      end
    end
```
