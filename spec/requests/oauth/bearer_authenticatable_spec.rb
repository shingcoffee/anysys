# frozen_string_literal: true

require "rails_helper"

# Admin::EntityDefinitionsController is the thinnest controller that includes
# the concern, so it stands in for every desktop Bearer API surface here.
RSpec.describe Oauth::BearerAuthenticatable, type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:path) { "/#{customer.id}/admin/entity_definitions" }

  def bearer_get(token, request_path = path, headers: {})
    get request_path, headers: { "Authorization" => "Bearer #{token}" }.merge(headers)
  end

  describe "cookie sessions" do
    it "never accepts a cookie in place of a token" do
      sign_in admin
      get path
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "does not set a session cookie on a successful bearer request" do
      bearer_get(desktop_access_token_for(admin))
      expect(response).to have_http_status(:ok)
      expect(response.headers["Set-Cookie"].to_s).not_to include("_anysys_session")
    end

    it "does not run browser sign-in callbacks or change tracking on repeated stateless requests" do
      token = desktop_access_token_for(admin)
      fields = %w[sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip remember_created_at]
      before = admin.attributes.slice(*fields)
      expect_any_instance_of(Authentication::User).not_to receive(:update_tracked_fields!)

      2.times do
        bearer_get(token)
        expect(response).to have_http_status(:ok)
        expect(response.headers["Set-Cookie"].to_s).not_to include("_anysys_session", "remember_user_token")
      end

      expect(admin.reload.attributes.slice(*fields)).to eq(before)
    end
  end

  describe "multi-tenant isolation" do
    let(:other_customer) { create(:customer) }

    it "blocks a token owner from reaching another tenant's URL" do
      bearer_get(desktop_access_token_for(admin), "/#{other_customer.id}/admin/entity_definitions")
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("access_denied")
    end

    it "blocks another tenant's admin from this tenant's URL" do
      stranger = create(:user, :admin, customer: other_customer)
      bearer_get(desktop_access_token_for(stranger))
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the platform owner cross tenants" do
      bearer_get(desktop_access_token_for(find_or_create_platform_owner))
      expect(response).to have_http_status(:ok)
    end
  end

  describe "token acceptance" do
    it "rejects a token issued to another OAuth application" do
      other = Doorkeeper::Application.create!(
        name: "Other", uid: "other-client", redirect_uri: "http://127.0.0.1/callback",
        confidential: false, scopes: Oauth::Protocol::SCOPE
      )
      bearer_get(desktop_access_token_for(admin, application: other))
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token without the profile scope" do
      token = Oauth::AccessToken.create_for(
        application: Oauth::DesktopClient.ensure!, resource_owner: admin, scopes: "",
        expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i
      )
      bearer_get(token.plaintext_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "keeps locked accounts ineligible when Warden callbacks are suppressed" do
      token = desktop_access_token_for(admin)
      admin.lock_access!

      bearer_get(token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
      expect(controller.current_user).to be_nil
    end

    it "keeps unconfirmed accounts ineligible without creating a request principal" do
      token = desktop_access_token_for(admin)
      admin.update!(confirmed_at: nil)

      bearer_get(token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
      expect(controller.current_user).to be_nil
    end

    it "still applies the admin role gate to a member token" do
      member = create(:user, :member, customer: customer)

      bearer_get(desktop_access_token_for(member))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("access_denied")
    end

    it "uses the token principal's role even when an administrator cookie is also present" do
      sign_in admin
      member = create(:user, :member, customer: customer)

      bearer_get(desktop_access_token_for(member))

      expect(response).to have_http_status(:forbidden)
      expect(controller.current_user.id).to eq(member.id)
    end
  end

  # ApplicationController declares `allow_browser versions: :modern`, which
  # Rails registers as an anonymous lambda before_action that cannot be named
  # in skip_before_action. The concern opts out by overriding the private
  # instance method that lambda calls; if Rails ever renames it the override
  # becomes dead and every desktop client starts getting 406.
  describe "Rails allow_browser opt-out" do
    it "still overrides a private method Rails actually calls" do
      expect(ActionController::AllowBrowser.private_method_defined?(:allow_browser)).to be true
      expect(ActionController::AllowBrowser.instance_method(:allow_browser).parameters)
        .to eq([%i[keyreq versions], %i[keyreq block]])
    end

    it "serves a desktop client whose User-Agent looks like an outdated browser" do
      bearer_get(
        desktop_access_token_for(admin),
        headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/90.0.4430.212" }
      )
      expect(response).to have_http_status(:ok)
    end
  end
end
