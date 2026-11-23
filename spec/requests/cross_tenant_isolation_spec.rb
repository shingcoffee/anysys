# frozen_string_literal: true

require "rails_helper"

# Cross-tenant isolation: a signed-in user must never reach another customer's
# tenant-scoped routes by simply changing the :customer_id segment in the URL.
# Only platform owners (customer 81_721_200, owner role) may cross tenants.
RSpec.describe "cross-tenant isolation", type: :request do
  let(:platform_customer) { ensure_platform_customer }
  let(:tenant_a)          { create(:customer, name: "A") }
  let(:tenant_b)          { create(:customer, name: "B") }

  let(:owner_a)         { create(:user, :admin, customer: tenant_a) }
  let(:platform_owner)  { find_or_create_platform_owner }

  before do
    platform_customer
    tenant_a
    tenant_b
  end

  describe "regular owner accessing another customer's admin routes" do
    before { sign_in owner_a }

    it "is denied on the dashboard" do
      get "/#{tenant_b.id}/admin/dashboard"
      expect(response).not_to have_http_status(:ok)
    end

    it "does not leak the cross-tenant customer in Current" do
      get "/#{tenant_b.id}/admin/dashboard"
      expect(Current.customer&.id).not_to eq(tenant_b.id)
    end
  end

  describe "regular owner accessing their OWN admin routes" do
    before { sign_in owner_a }

    it "still works for the dashboard" do
      get "/#{tenant_a.id}/admin/dashboard"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
    end
  end

  describe "platform owner accessing another customer's admin routes" do
    before { sign_in platform_owner }

    it "is allowed on the dashboard" do
      get "/#{tenant_a.id}/admin/dashboard"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
    end

    it "is allowed to reach the target tenant (platform owner cross-tenant access)" do
      # Platform owner context is rebuilt from the URL per request rather
      # than stored in the session, so we assert through the response: a
      # non-platform owner would have been redirected/forbidden.
      get "/#{tenant_a.id}/admin/dashboard"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
      expect(response).not_to have_http_status(:forbidden)
      if response.redirect?
        # Should never redirect to a denial path back to the user's own tenant.
        expect(response.location).not_to match(%r{/#{platform_customer.id}\b})
      end
    end
  end

  describe "platform CustomerContextsController explicit guard" do
    it "blocks a non-platform-owner from switching tenants" do
      sign_in owner_a
      patch admin_maintenance_platform_customer_context_path(tenant_a.id),
            params: { customer_id: tenant_b.id }
      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "render_tenant_not_found_error — JSON format" do
    it "returns JSON 404 with error details for an unknown customer_id via JSON request" do
      # Use a non-existent customer id in a JSON request so auto_set_tenant_from_path
      # fires render_tenant_not_found_error in JSON format.
      get "/99999999/admin/dashboard",
          headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
      json = response.parsed_body
      expect(json["error"]).to eq("Customer not found")
    end
  end

  describe "render_tenant_forbidden_error — JSON format" do
    it "returns JSON 403 when a non-owner accesses another tenant's URL via JSON" do
      sign_in owner_a
      get "/#{tenant_b.id}/admin/dashboard",
          headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      json = response.parsed_body
      expect(json["error"]).to eq("access_denied")
    end
  end

  describe "clear_platform_owner_context — CustomerContextsController#destroy" do
    let(:platform_owner) { find_or_create_platform_owner }

    before do
      platform_customer
      sign_in platform_owner
    end

    it "clears platform owner context and redirects to own dashboard" do
      delete admin_maintenance_platform_customer_context_path(platform_customer.id)
      expect(response).to redirect_to("/#{platform_owner.customer_id}/admin/dashboard")
    end
  end
end
