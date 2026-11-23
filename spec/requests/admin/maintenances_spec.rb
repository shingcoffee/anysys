# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenances#show", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/maintenance" }

  it_behaves_like "an admin-guarded GET"

    it "renders 200 with the Maintenance heading and the nav cards" do
      get "/#{customer.id}/admin/maintenance"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Maintenance")
      expect(response.body).to include("Manage definitions and system configuration")

      # Nav card headings — flowcharts are owner-only
      %w[Entities Pages Constants Modules].each do |label|
        expect(response.body).to include(label)
      end
      expect(response.body).not_to include(I18n.t("admin_misc.maintenance.cards.flowcharts_title"))
      expect(response.body).to include("Customer Profile")

      # Nav card links point at the expected paths
      expect(response.body).to include(admin_maintenance_entities_path(customer.id))
      expect(response.body).not_to include(admin_maintenance_flowcharts_path(customer.id))
      expect(response.body).to include(admin_maintenance_pages_path(customer.id))
      expect(response.body).to include(admin_maintenance_constants_path(customer.id))
      expect(response.body).to include(admin_maintenance_modules_path(customer.id))
      expect(response.body).to include(admin_maintenance_customer_profile_path(customer.id))
    end

    it "expands the left sidebar by default even when a collapsed cookie was set earlier" do
      cookies["sidebar_state_maintenance"] = "collapsed"
      get "/#{customer.id}/admin/maintenance"

      body = Capybara.string(response.body)
      expect(body).to have_css("#app-sidebar[data-state='expanded'][data-sidebar-collapsible-collapsed-value='false']")
    end

    it "shows the Flowcharts card to the platform owner" do
      sign_in find_or_create_platform_owner
      get "/#{customer.id}/admin/maintenance"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin_misc.maintenance.cards.flowcharts_title"))
      expect(response.body).to include(admin_maintenance_flowcharts_path(customer.id))
    end

  it "allows the platform owner cross-tenant" do
    sign_in find_or_create_platform_owner
    get guard_path
    expect(response).to have_http_status(:ok)
  end
end
