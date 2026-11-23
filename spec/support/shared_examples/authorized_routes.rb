# frozen_string_literal: true

# Auth-guard assertions for request specs. The host must define `guard_path`
# and typically `include_context "as admin"` (or `"admin records"` plus a
# signed-in admin). Anonymous examples sign the admin out first.
#
#   let(:guard_path) { admin_dashboards_path(customer.id) }
#   it_behaves_like "an admin-guarded GET"
#
# Optional second argument / `http_method:` for POST/PATCH/DELETE:
#   it_behaves_like "an admin-guarded request", :post

RSpec.shared_examples "an admin-guarded request" do |http_method = :get|
  it "redirects anonymous users to sign in" do
    sign_out(admin) if respond_to?(:sign_out)
    public_send(http_method, guard_path)
    expect(response).to have_http_status(:found).or have_http_status(:unauthorized)
  end

  it "forbids a member" do
    sign_in create(:user, :member, customer: customer)
    public_send(http_method, guard_path)
    expect(response).to have_http_status(:forbidden)
      .or have_http_status(:found)
      .or have_http_status(:not_found)
  end
end

RSpec.shared_examples "an admin-guarded GET" do
  it_behaves_like "an admin-guarded request", :get
end

# Owner-only Maintenance / Platform routes. Host defines `guard_path` (the
# platform-customer URL). Anonymous examples sign out `platform_owner`,
# `owner`, or `admin` when present. Tenant admin/member are created on a
# fresh customer and must not receive :ok.
#
#   let(:guard_path) { admin_maintenance_platform_announcements_path(platform_cid) }
#   it_behaves_like "a platform-owner-guarded GET"
#
# Optional second argument / `http_method:` for POST/PATCH/DELETE:
#   it_behaves_like "a platform-owner-guarded request", :patch
RSpec.shared_examples "a platform-owner-guarded request" do |http_method = :get|
  it "redirects anonymous users to sign in" do
    actor = if respond_to?(:platform_owner)
      platform_owner
    elsif respond_to?(:owner)
      owner
    elsif respond_to?(:admin)
      admin
    end
    sign_out(actor) if actor && respond_to?(:sign_out)
    public_send(http_method, guard_path)
    expect(response).to have_http_status(:found).or have_http_status(:unauthorized)
  end

  it "forbids a member" do
    sign_in create(:user, :member, customer: create(:customer))
    public_send(http_method, guard_path)
    expect(response).not_to have_http_status(:ok)
  end

  it "forbids a tenant admin" do
    sign_in create(:user, :admin, customer: create(:customer))
    public_send(http_method, guard_path)
    expect(response).not_to have_http_status(:ok)
  end
end

RSpec.shared_examples "a platform-owner-guarded GET" do
  it_behaves_like "a platform-owner-guarded request", :get
end

# Location extra for flowchart editor surfaces. Shared HTTP guards cover
# status; this asserts the redirect leaves the editor URL.
RSpec.shared_examples "redirects anonymous away from flowchart editor" do |http_method = :get|
  it "redirects away from the flowchart editor" do
    actor = if respond_to?(:platform_owner)
      platform_owner
    elsif respond_to?(:admin)
      admin
    end
    sign_out(actor) if actor && respond_to?(:sign_out)
    public_send(http_method, guard_path)
    expect(response.location).not_to include("/admin/maintenance/flowcharts")
  end
end

# Back-compat aliases. Prefer the host `guard_path` forms above.
RSpec.shared_examples "requires authentication" do |http_method = :get|
  it_behaves_like "an admin-guarded request", http_method
end
