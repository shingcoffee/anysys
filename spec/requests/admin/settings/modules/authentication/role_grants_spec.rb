# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication/role_grants", type: :request do
  include_context "as admin"

  let(:owner_role)  { customer.roles.find_by(key: "owner") }
  let(:custom_role) { create(:role, customer: customer, key: "manager", name: "Manager") }
  let(:locked_role) { customer.roles.find_by(key: "admin") }
  let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles/#{custom_role.id}/grants" }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  describe "GET show" do
    it "renders the grants editor" do
      get "/#{customer.id}/admin/settings/modules/authentication/roles/#{custom_role.id}/grants"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Manager")
    end
  end

  describe "PATCH update" do
    it "applies the grants diff" do
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{custom_role.id}/grants",
            params: {
              role_grants: {
                added:   [{ subject_type: "Route", subject_key: "admin/maintenance/pages", action: "read" }],
                removed: []
              }
            }, as: :json
      expect(response).to have_http_status(:success)
      expect(custom_role.role_permissions.count).to eq(1)
    end

    it "rejects updates to locked roles" do
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{locked_role.id}/grants",
            params: { role_grants: { added: [{ subject_type: "Route", subject_key: "x", action: "read" }], removed: [] } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects minting a flowchart route grant" do
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{custom_role.id}/grants",
            params: {
              role_grants: {
                added:   [{ subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read" }],
                removed: []
              }
            }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]["base"]).to include(I18n.t("auth.errors.platform_grant_forbidden"))
      expect(custom_role.role_permissions).to be_empty
    end
  end
end
