# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member (hub)", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/settings/member" }

  before do
    enable_module!("payment", customer, name: "Payments")
  end

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  describe "GET /:cid/admin/settings/member" do
    it "links to core pages, member modules, and record pages" do
      get "/#{customer.id}/admin/settings/member"
      expect(response).to have_http_status(:ok)
      %w[builtin modules entities].each do |source|
        section = Capybara.string(response.body).find("section", text: I18n.t("settings_people.sources.#{source}.name"))
        expect(section).to have_link(
          I18n.t(source == "builtin" ? "common.actions.view" : "comp_admin.member_hub_card.configure"),
          href: "/#{customer.id}/admin/settings/member/sources/#{source}"
        )
      end
    end
  end

  describe "PATCH /:cid/admin/settings/member" do
    it "persists row updates and redirects to the hub" do
      patch "/#{customer.id}/admin/settings/member",
            params: {
              member_settings: {
                rows: [{ surface_key: "payments", enabled: "1", label: "Donations" }]
              }
            }

      expect(response).to redirect_to("/#{customer.id}/admin/settings/member")
      row = Member::SurfaceSetting.find_by!(customer: customer, surface_key: "payments")
      expect(row.source_key).to eq("modules")
      expect(row.enabled).to be(true)
    end

    it "re-renders with 422 when the operation fails" do
      patch "/#{customer.id}/admin/settings/member",
            params: {
              member_settings: {
                rows: [{ surface_key: "phantom", enabled: "1" }]
              }
            }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
