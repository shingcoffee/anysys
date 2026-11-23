# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth 2.0 PKCE for the desktop client", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:user) { create(:user, :admin, customer: customer, password: "password123") }
  let(:loopback_uri) { "http://127.0.0.1:41831/callback" }
  let(:pkce) { pkce_pair }
  let(:verifier) { pkce[0] }
  let(:challenge) { pkce[1] }
  let(:state) { oauth_state }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    Oauth::DesktopClient.ensure!
  end

  def start_authorize(redirect_uri: loopback_uri, extra: {})
    get "/oauth/authorize", params: authorize_params(
      challenge: challenge, state: state, redirect_uri: redirect_uri, extra: extra
    )
  end

  def exchange_code(code, redirect_uri: loopback_uri, code_verifier: verifier)
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: Oauth::Protocol::CLIENT_ID,
      code_verifier: code_verifier
    }
  end

  describe "GET /.well-known/oauth-authorization-server" do
    it "returns RFC 8414 metadata for the public PKCE client" do
      get "/.well-known/oauth-authorization-server"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["authorization_endpoint"]).to end_with("/oauth/authorize")
      expect(body["token_endpoint"]).to end_with("/oauth/token")
      expect(body["revocation_endpoint"]).to end_with("/oauth/revoke")
      expect(body["userinfo_endpoint"]).to end_with("/oauth/userinfo")
      expect(body["code_challenge_methods_supported"]).to eq(["S256"])
      expect(body["token_endpoint_auth_methods_supported"]).to eq(["none"])
      expect(body["grant_types_supported"]).to include("authorization_code", "refresh_token")
    end

    it "is publicly cacheable — it is static and identical for every caller" do
      get "/.well-known/oauth-authorization-server"
      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.headers["Cache-Control"]).to include("max-age=3600")
      expect(response.headers["Vary"].to_s.split(/[\s,]+/)).to include("Host")
    end

    it "does not take issuer from a spoofed Host when APP_HOST is set" do
      ClimateControl.modify(APP_HOST: "canonical.example") do
        get "/.well-known/oauth-authorization-server", headers: { "Host" => "evil.example" }
        body = response.parsed_body
        expect(body["issuer"]).to eq("http://canonical.example")
        expect(body["authorization_endpoint"]).to eq("http://canonical.example/oauth/authorize")
        expect(body["issuer"]).not_to include("evil.example")
      end
    end
  end

  describe "GET /oauth/authorize" do
    it "redirects anonymous users to sign-in and stores the authorize URL" do
      start_authorize
      expect(response).to redirect_to(new_user_session_path)
      expect(session["user_return_to"]).to start_with("/oauth/authorize")
    end

    it "rejects a missing state parameter" do
      sign_in user
      get "/oauth/authorize", params: authorize_params(
        challenge: challenge, state: "short", redirect_uri: loopback_uri
      )
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects PKCE method plain" do
      sign_in user
      start_authorize(extra: { code_challenge_method: "plain", code_challenge: verifier })
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a non-loopback redirect_uri" do
      sign_in user
      start_authorize(redirect_uri: "https://evil.example/callback")
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a response_mode the loopback handoff cannot deliver" do
      sign_in user
      start_authorize(extra: { response_mode: "fragment" })
      expect(response).to have_http_status(:bad_request)
    end

    # RFC 8252 §7.3 / Doorkeeper URIChecker.matches?: when both the registered
    # and requested URIs are loopback the port is ignored, which is the only
    # reason a single registration can serve every ephemeral desktop port.
    it "accepts any ephemeral loopback port against the port-less registration" do
      sign_in user
      start_authorize(redirect_uri: "http://127.0.0.1:59999/callback")
      expect(response).to have_http_status(:ok)
      expect(oauth_callback_uri).to start_with("http://127.0.0.1:59999/callback")
    end

    it "still rejects a loopback callback on the wrong path" do
      sign_in user
      start_authorize(redirect_uri: "http://127.0.0.1:59999/steal")
      expect(response).to have_http_status(:bad_request)
    end

    # family_started_at is a configured custom access token attribute, which
    # Doorkeeper would otherwise read straight out of the authorize query and
    # write to the access grant (a table with no such column).
    it "ignores a client-supplied refresh-family clock" do
      sign_in user
      start_authorize(extra: { family_started_at: 5.years.from_now.iso8601 })
      expect(response).to have_http_status(:ok)

      code = extract_redirect_query(oauth_callback_uri)["code"]
      exchange_code(code)
      expect(response).to have_http_status(:ok)
      expect(Oauth::AccessToken.last.family_started_at).to be_within(1.minute).of(Time.current)
    end

    it "issues an authorization code via an HTML handoff to the loopback callback" do
      sign_in user
      start_authorize
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.headers["Cache-Control"]).to include("no-store")
      location = oauth_callback_uri
      expect(location).to start_with(loopback_uri)
      query = extract_redirect_query(location)
      expect(query["state"]).to eq(state)
      expect(query["code"]).to be_present
    end

    it "rejects an authorization session snapshot replaced before grant issuance" do
      sign_in user
      changed = false
      allow(Authentication::CredentialLifecycle).to receive(:with_current).and_wrap_original do |method, account, &block|
        if account.id == user.id && !changed
          changed = true
          Authentication::User.find(user.id).update!(
            password: "ChangedPassword1!", password_confirmation: "ChangedPassword1!"
          )
        end
        method.call(account, &block)
      end

      expect { start_authorize }.not_to change(Doorkeeper::AccessGrant, :count)

      expect(response).to have_http_status(:conflict)
      expect(response.body).to eq(I18n.t("auth.errors.credentials_changed"))
      expect(response.body).not_to include("data-oauth-native-handoff-url-value")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(user.reload.valid_password?("ChangedPassword1!")).to be(true)
    end

    # The handoff page's meta refresh and continue link both point at a URL
    # containing the authorization code, so the browser must not attach it to a
    # Referer header, and no cache may keep the page.
    it "keeps the authorization code out of Referer and out of caches" do
      sign_in user
      start_authorize

      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Pragma"]).to eq("no-cache")
      expect(response.body).to include('<meta name="referrer" content="no-referrer">')
      expect(response.body).to include('rel="noreferrer"')
    end

    it "issues an authorization code to an IPv6 loopback callback" do
      ipv6 = "http://[::1]:41832/callback"
      sign_in user
      start_authorize(redirect_uri: ipv6)
      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(oauth_callback_uri).to start_with(ipv6)
    end

    it "returns HTML (not a 302) when Turbo asks for a stream so the loopback hop is not swallowed" do
      sign_in user
      get "/oauth/authorize",
          params: authorize_params(challenge: challenge, state: state, redirect_uri: loopback_uri),
          headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(response.media_type).to eq("text/html")
      expect(oauth_callback_uri).to start_with(loopback_uri)
    end

    it "returns the user to authorize after password sign-in" do
      start_authorize
      expect(response).to redirect_to(new_user_session_path)

      post user_session_path, params: { user: { email: user.email, password: "password123" } }
      expect(response).to be_redirect
      expect(response.location).to include("/oauth/authorize")

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(oauth_callback_uri).to start_with(loopback_uri)
    end
  end

  describe "POST /oauth/authorize" do
    before { sign_in user }

    [nil, "short"].each do |invalid_state|
      it "rejects #{invalid_state.inspect} state on consent POST without issuing a code" do
        expect {
          post "/oauth/authorize", params: authorize_params(
            challenge: challenge, state: invalid_state, redirect_uri: loopback_uri
          )
        }.not_to change(Doorkeeper::AccessGrant, :count)

        expect(response).to have_http_status(:bad_request)
        expect(response).not_to be_redirect
        expect(response.body).not_to include("data-oauth-native-handoff-url-value")
      end
    end

    %w[fragment form_post].each do |response_mode|
      it "rejects #{response_mode} response mode on consent POST without issuing a code" do
        expect {
          post "/oauth/authorize", params: authorize_params(
            challenge: challenge, state: state, redirect_uri: loopback_uri,
            extra: { response_mode: response_mode }
          )
        }.not_to change(Doorkeeper::AccessGrant, :count)

        expect(response).to have_http_status(:bad_request)
        expect(response).not_to be_redirect
        expect(response.body).not_to include("data-oauth-native-handoff-url-value")
      end
    end

    it "preserves a valid query-mode consent POST and binds the code to state" do
      expect {
        post "/oauth/authorize", params: authorize_params(
          challenge: challenge, state: state, redirect_uri: loopback_uri,
          extra: { response_mode: "query" }
        )
      }.to change(Doorkeeper::AccessGrant, :count).by(1)

      expect(response).to have_http_status(:ok)
      callback = URI.parse(oauth_callback_uri)
      expect(callback.fragment).to be_nil
      query = extract_redirect_query(oauth_callback_uri)
      expect(query["state"]).to eq(state)
      expect(query["code"]).to be_present
    end

    it "does not captcha-block the consent POST while under the URL throttle" do
      Captcha::Providers::Aliyun
      create(:captcha_provider_settings, enabled: true)

      post "/oauth/authorize", params: authorize_params(
        challenge: challenge, state: state, redirect_uri: loopback_uri
      )

      expect(response).not_to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /oauth/authorize" do
    before { sign_in user }

    ["https://evil.example/callback", "http://127.0.0.1:59999/steal", "//evil.example/callback", "http://[", nil].each do |redirect_uri|
      it "rejects an unregistered denial destination #{redirect_uri.inspect} without handing it off" do
        expect {
          delete "/oauth/authorize", params: authorize_params(
            challenge: challenge, state: state, redirect_uri: redirect_uri
          )
        }.not_to change(Doorkeeper::AccessGrant, :count)

        expect(response).to have_http_status(:bad_request)
        expect(response).not_to be_redirect
        expect(response.body).not_to include("data-oauth-native-handoff-url-value")
      end
    end

    it "rejects an unknown client before handing a denial to its loopback URI" do
      delete "/oauth/authorize", params: authorize_params(
        challenge: challenge, state: state, redirect_uri: loopback_uri,
        extra: { client_id: "unknown-client" }
      )

      expect(response).to have_http_status(:unauthorized)
      expect(response).not_to be_redirect
      expect(response.body).not_to include("data-oauth-native-handoff-url-value")
    end

    it "rejects a registered client that is not the desktop client" do
      other = Doorkeeper::Application.create!(
        name: "Other", uid: "other-denial-client", redirect_uri: "http://127.0.0.1/callback",
        confidential: false, scopes: Oauth::Protocol::SCOPE
      )
      delete "/oauth/authorize", params: authorize_params(
        challenge: challenge, state: state, redirect_uri: loopback_uri,
        extra: { client_id: other.uid }
      )

      expect(response).to have_http_status(:unauthorized)
      expect(response).not_to be_redirect
      expect(response.body).not_to include("data-oauth-native-handoff-url-value")
    end

    it "rejects a denial without response-binding state" do
      delete "/oauth/authorize", params: authorize_params(
        challenge: challenge, state: nil, redirect_uri: loopback_uri
      )

      expect(response).to have_http_status(:bad_request)
      expect(response).not_to be_redirect
      expect(response.body).not_to include("data-oauth-native-handoff-url-value")
    end

    it "rejects a denial requesting fragment delivery" do
      delete "/oauth/authorize", params: authorize_params(
        challenge: challenge, state: state, redirect_uri: loopback_uri,
        extra: { response_mode: "fragment" }
      )

      expect(response).to have_http_status(:bad_request)
      expect(response).not_to be_redirect
      expect(response.body).not_to include("data-oauth-native-handoff-url-value")
    end

    ["http://127.0.0.1:59999/callback", "http://[::1]:41832/callback"].each do |redirect_uri|
      it "hands a valid denial back to #{redirect_uri} with state and no authorization code" do
        expect {
          delete "/oauth/authorize", params: authorize_params(
            challenge: challenge, state: state, redirect_uri: redirect_uri
          )
        }.not_to change(Doorkeeper::AccessGrant, :count)

        expect(response).to have_http_status(:ok)
        expect(oauth_callback_uri).to start_with(redirect_uri)
        query = extract_redirect_query(oauth_callback_uri)
        expect(query["error"]).to eq("access_denied")
        expect(query["state"]).to eq(state)
        expect(query).not_to have_key("code")
        expect(response.headers["Cache-Control"]).to include("no-store")
        expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      end
    end
  end

  describe "token + userinfo + refresh + revoke" do
    def issued_tokens
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      exchange_code(code)
      response.parsed_body
    end

    it "exchanges a PKCE code for access and refresh tokens" do
      body = issued_tokens
      expect(response).to have_http_status(:ok)
      expect(body["token_type"]).to eq("Bearer")
      expect(body["expires_in"]).to eq(3600)
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(body["scope"]).to eq("profile")
    end

    it "locks the resource owner before the authorization grant and exchanges the code only once" do
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      locks = []
      allow_any_instance_of(Authentication::User).to receive(:with_lock).and_wrap_original do |method, *args, **kwargs, &block|
        locks << :user if method.receiver.id == user.id
        method.call(*args, **kwargs, &block)
      end
      allow_any_instance_of(Doorkeeper::AccessGrant).to receive(:lock!).and_wrap_original do |method, *args|
        locks << :grant
        method.call(*args)
      end

      expect { exchange_code(code) }.to change(Oauth::AccessToken, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(locks).to eq(%i[user grant])
      expect(response.parsed_body["access_token"]).to be_present
    end

    it "returns invalid_grant for a code lookup that became stale after a credential change" do
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      grant_model = Doorkeeper.config.access_grant_model
      stale_grant = grant_model.by_token(code)
      user.update!(password: "ChangedPassword1!", password_confirmation: "ChangedPassword1!")
      allow(grant_model).to receive(:by_token).with(code).and_return(stale_grant)

      expect { exchange_code(code) }.not_to change(Oauth::AccessToken, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
      expect(stale_grant.reload).to be_revoked
    end

    it "keeps the standard invalid-grant response for an unknown authorization code" do
      expect { exchange_code("unknown-authorization-code") }.not_to change(Oauth::AccessToken, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "returns structured 400 for an expired unredeemed authorization code" do
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      grant = Doorkeeper.config.access_grant_model.by_token(code)
      grant.update!(created_at: 20.minutes.ago)

      expect { exchange_code(code) }.not_to change(Oauth::AccessToken, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
      expect(response.parsed_body["error_description"]).to be_present
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "returns structured 400 if an unredeemed code's owner cannot be resolved" do
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      allow(Authentication::User).to receive(:find_by).with(id: user.id).and_return(nil)

      expect { exchange_code(code) }.not_to change(Oauth::AccessToken, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
      expect(response.parsed_body["error_description"]).to be_present
    end

    it "rejects an unredeemed code revoked by a password change through the actual token endpoint" do
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      grant = Doorkeeper.config.access_grant_model.by_token(code)
      user.update!(password: "ChangedPassword1!", password_confirmation: "ChangedPassword1!")

      expect { exchange_code(code) }.not_to change(Oauth::AccessToken, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
      expect(grant.reload).to be_revoked
    end

    it "returns structured invalid_grant when a refresh token's account lookup no longer resolves" do
      tokens = issued_tokens
      allow(Authentication::User).to receive(:find_by).with(id: user.id).and_return(nil)

      expect {
        post "/oauth/token", params: {
          grant_type: "refresh_token", refresh_token: tokens["refresh_token"],
          client_id: Oauth::Protocol::CLIENT_ID
        }
      }.not_to change(Oauth::AccessToken, :count)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "filters the submitted authorization code from request logging without changing token exchange" do
      tokens = issued_tokens

      expect(response).to have_http_status(:ok)
      expect(tokens["access_token"]).to be_present
      expect(controller.request.filtered_parameters["code"]).to eq("[FILTERED]")
      expect(controller.request.filtered_parameters["code_verifier"]).to eq("[FILTERED]")
    end

    it "rejects a mismatched code_verifier" do
      sign_in user
      start_authorize
      code = extract_redirect_query(oauth_callback_uri)["code"]
      exchange_code(code, code_verifier: "a" * 43)
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "returns userinfo for a valid Bearer token" do
      tokens = issued_tokens
      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["sub"]).to eq(user.id.to_s)
      expect(body["email"]).to eq(user.email)
      expect(body["customer_id"]).to eq(customer.id.to_s)
      expect(body["role"]).to eq("admin")
      expect(body["name"]).to eq(user.display_name)
    end

    it "rejects userinfo without a Bearer token" do
      get "/oauth/userinfo"
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "never lets an intermediary cache the identity document" do
      tokens = issued_tokens
      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.headers["Pragma"]).to eq("no-cache")
    end

    it "rejects a token that lacks the profile scope" do
      token = Oauth::AccessToken.create_for(
        application: Oauth::DesktopClient.ensure!, resource_owner: user, scopes: "",
        expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i
      )
      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("insufficient_scope")
    end

    it "rejects a token issued to another OAuth client" do
      other = Doorkeeper::Application.create!(
        name: "Other", uid: "other-client", redirect_uri: "http://127.0.0.1/callback",
        confidential: false, scopes: Oauth::Protocol::SCOPE
      )
      get "/oauth/userinfo",
          headers: { "Authorization" => "Bearer #{desktop_access_token_for(user, application: other)}" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "rejects a token whose owner was deactivated" do
      token = desktop_access_token_for(user)
      user.inactive!
      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rotates the refresh token and rejects reuse of the previous one" do
      tokens = issued_tokens
      old_refresh = tokens["refresh_token"]

      post "/oauth/token", params: {
        grant_type: "refresh_token",
        refresh_token: old_refresh,
        client_id: Oauth::Protocol::CLIENT_ID
      }
      expect(response).to have_http_status(:ok)
      rotated = response.parsed_body
      expect(rotated["refresh_token"]).to be_present
      expect(rotated["refresh_token"]).not_to eq(old_refresh)

      post "/oauth/token", params: {
        grant_type: "refresh_token",
        refresh_token: old_refresh,
        client_id: Oauth::Protocol::CLIENT_ID
      }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")

      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{rotated['access_token']}" }
      expect(response).to have_http_status(:unauthorized)
    end

    def refresh(token)
      post "/oauth/token", params: {
        grant_type: "refresh_token", refresh_token: token, client_id: Oauth::Protocol::CLIENT_ID
      }
      response.parsed_body
    end

    it "keeps the family clock across rotations so the absolute TTL stays anchored" do
      tokens = issued_tokens
      anchor = Oauth::AccessToken.order(:id).last.family_started_at
      expect(anchor).to be_present

      refresh(tokens["refresh_token"])

      expect(Oauth::AccessToken.order(:id).last.family_started_at).to eq(anchor)
    end

    # Reuse of one stale refresh token must not act as a remote logout button
    # for every other device the user has signed in on this client.
    it "confines reuse revocation to the offending session" do
      laptop = issued_tokens
      phone = issued_tokens

      rotated = refresh(laptop["refresh_token"])
      expect(response).to have_http_status(:ok)

      refresh(laptop["refresh_token"])
      expect(response).to have_http_status(:bad_request)

      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{rotated['access_token']}" }
      expect(response).to have_http_status(:unauthorized)

      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{phone['access_token']}" }
      expect(response).to have_http_status(:ok)
    end

    it "revokes a refresh token (RFC 7009)" do
      tokens = issued_tokens
      post "/oauth/revoke", params: {
        token: tokens["refresh_token"],
        token_type_hint: "refresh_token",
        client_id: Oauth::Protocol::CLIENT_ID
      }
      expect(response).to have_http_status(:ok)

      post "/oauth/token", params: {
        grant_type: "refresh_token",
        refresh_token: tokens["refresh_token"],
        client_id: Oauth::Protocol::CLIENT_ID
      }
      expect(response).to have_http_status(:bad_request)
    end

    it "does not family-revoke when a already-rotated refresh token is presented to /oauth/revoke" do
      tokens = issued_tokens
      rotated = refresh(tokens["refresh_token"])
      expect(response).to have_http_status(:ok)

      post "/oauth/revoke", params: {
        token: tokens["refresh_token"],
        token_type_hint: "refresh_token",
        client_id: Oauth::Protocol::CLIENT_ID
      }
      expect(response).to have_http_status(:ok)

      get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{rotated['access_token']}" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "MFA resume" do
    let!(:mfa_user) { create(:user, :admin, :with_mfa, customer: customer, password: "password123") }

    it "completes authorize after TOTP" do
      start_authorize
      post user_session_path, params: {
        user: { email: mfa_user.email, password: "password123" }
      }
      expect(response).to redirect_to(mfa_session_path(customer.id))

      post mfa_session_path(customer.id),
           params: { otp_code: ROTP::TOTP.new(mfa_user.otp_secret).now }
      expect(response).to be_redirect
      expect(response.location).to include("/oauth/authorize")

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(oauth_callback_uri).to start_with(loopback_uri)
    end
  end

  describe "inactive user" do
    it "does not issue a code" do
      user.inactive!
      sign_in user
      start_authorize
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
