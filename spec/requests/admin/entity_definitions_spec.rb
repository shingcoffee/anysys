# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin entity definitions desktop API", type: :request do
  include_context "admin records"
  let(:path) { "/#{customer.id}/admin/entity_definitions" }

  def bearer_get(token, request_path = path, extra_headers: {})
    get request_path, headers: { "Authorization" => "Bearer #{token}" }.merge(extra_headers)
  end

  describe "GET /:cid/admin/entity_definitions" do
    it "returns the tenant's resolved entity definitions for a desktop Bearer token" do
      entity = create(:entity, :with_name_status_schema, customer: customer, name: "Contact")

      bearer_get(desktop_access_token_for(admin))

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      body = response.parsed_body
      expect(body["entities"].size).to eq(1)
      item = body["entities"].first
      expect(item["id"]).to eq(entity.id)
      expect(item["name"]).to eq("Contact")
      expect(item["property_schema"]).to be_an(Array)
      expect(item["property_schema"].size).to eq(2)
      expect(item["current_version"]["version_number"]).to be_present
    end

    it "rejects a missing Bearer token even when a cookie session exists" do
      sign_in admin
      get path
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "rejects an invalid token" do
      bearer_get("not-a-token")
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "rejects a token issued to a different OAuth client" do
      other_app = Doorkeeper::Application.create!(
        name: "Other",
        uid: "other-client",
        redirect_uri: "http://127.0.0.1/callback",
        confidential: false,
        scopes: "profile"
      )
      bearer_get(desktop_access_token_for(admin, application: other_app))
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an inactive resource owner" do
      token = desktop_access_token_for(admin)
      admin.inactive!
      bearer_get(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids a member token" do
      member = create(:user, :member, customer: customer)
      bearer_get(desktop_access_token_for(member))
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("access_denied")
    end

    it "forbids a same-role admin from another tenant" do
      other = create(:customer)
      stranger = create(:user, :admin, customer: other)
      bearer_get(desktop_access_token_for(stranger))
      expect(response).to have_http_status(:forbidden)
    end

    it "allows the platform owner to list another tenant's definitions" do
      owner = find_or_create_platform_owner
      create(:entity, customer: customer, name: "Owned")

      bearer_get(desktop_access_token_for(owner))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["entities"].map { |row| row["name"] }).to include("Owned")
    end

    it "does not redirect an MFA-required user to the MFA page" do
      mfa_admin = create(:user, :admin, :with_mfa, customer: customer)
      bearer_get(desktop_access_token_for(mfa_admin))
      expect(response).to have_http_status(:ok)
    end

    it "accepts a non-modern desktop User-Agent" do
      bearer_get(
        desktop_access_token_for(admin),
        extra_headers: {
          "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/90.0.4430.212"
        }
      )
      expect(response).to have_http_status(:ok)
    end
  end
end
