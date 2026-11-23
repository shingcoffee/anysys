# frozen_string_literal: true

require "rails_helper"

# Locks in the three-layer authorization contract for /:cid/member/*
# pages. Layers 7.1 (URL+role) and 7.2 (tenant) are owned by the global
# RouteAuthorization and TenantContext concerns, NOT by Member::BaseController.
# See docs/superpowers/specs/2026-05-15-member-skeleton-design.md §7.
RSpec.describe "Member base authorization", type: :request do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:member_user)    { create(:user, :member, customer: customer) }
  let(:admin_user)     { create(:user, :admin, customer: customer) }
  let(:dashboard_url)  { "/#{customer.id}/member" }

  def enable_authentication_for(*customers)
    customers.each { |c| enable_module!("authentication", c, name: "Authentication") }
  end

  before { enable_authentication_for(customer, other_customer) }

  context "anonymous user" do
    it "is redirected to the customer sign-in page" do
      get dashboard_url
      expect(response).to redirect_to("/auth/sign_in")
    end
  end

  context "admin user visiting a member URL in their own tenant" do
    before { sign_in admin_user }

    it "is rejected by the role gate and sent to the admin surface" do
      get dashboard_url
      expect(response).to redirect_to("/#{customer.id}/admin/assistant")
      expect(flash[:alert]).to match(/member/i)
    end
  end

  context "owner user visiting a member URL in their own tenant" do
    let(:owner_user) { find_or_create_platform_owner }

    before do
      enable_authentication_for(owner_user.customer)
      sign_in owner_user
    end

    it "is rejected by the role gate (owners are not members)" do
      get "/#{owner_user.customer_id}/member"
      expect(response).to redirect_to("/#{owner_user.customer_id}/admin/assistant")
      expect(flash[:alert]).to match(/member/i)
    end
  end

  context "member of customer A visiting customer B's URL" do
    before { sign_in member_user }

    # Back to the member's OWN tenant, on the surface their role can open.
    # The old destination was /admin/dashboard, which the role gate would
    # then deny all over again.
    it "is rejected by the tenant gate and sent to their own member surface" do
      get "/#{other_customer.id}/member"
      expect(response).to redirect_to("/#{member_user.customer_id}/member")
      expect(flash[:alert]).to match(/access denied/i)
    end
  end

  context "member visiting their own member URL" do
    before { sign_in member_user }

    it "succeeds and renders the dashboard layout" do
      get dashboard_url
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-shell=\"member\"")
    end
  end
end
