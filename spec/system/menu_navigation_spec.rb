# frozen_string_literal: true

require "rails_helper"

# Uses request-type coverage (not full Capybara system test) because the
# rspec-rails system-test harness isn't wired up in this project. Verifies
# the rendered menu HTML, which is sufficient for non-JS assertions about
# menu item visibility per role.
RSpec.describe "Dashboard menu navigation", type: :request do
  let(:customer) { create(:customer) }

  before { FeatureModules::Authentication::Registration.register! }

  def sign_in_as(role)
    user = create(:user, customer: customer, role: role)
    sign_in user
    user
  end

  it "members are denied access to admin dashboard" do
    sign_in_as(:member)
    get "/#{customer.id}/admin/dashboard"

    # Access denials are tenant-aware: the user is bounced to a surface they
    # can actually open, not the marketing root, so they keep their context.
    # This used to assert "/#{customer.id}", which has no route at all — every
    # HTML denial landed the user on a routing error rather than a usable page.
    expect(response).to redirect_to("/#{customer.id}/member")
  end

  def expect_menu_labels(keys)
    document = Nokogiri::HTML(response.body)
    menu = document.css("nav[aria-label='Dashboard menu']").find { |nav| nav.at_css("[data-menu-item]") }
    expect(menu).to be_present
    keys.each do |key|
      item = menu.at_css("[data-menu-item='#{key}']")
      expect(item).to be_present
      expect(item.text.squish).to include(I18n.t("chrome.menu_bar.items.#{key}"))
    end
    expect(menu.at_css("[data-menu-item='account']")).to be_nil
  end

  it "admins see universal menu destinations with their current localized labels" do
    sign_in_as(:admin)
    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect_menu_labels(%i[home assistant users entities modules settings])
    expect(Nokogiri::HTML(response.body).at_css("nav[aria-label='Dashboard menu'] [data-menu-item='maintenance']")).to be_nil
  end

  it "the platform owner sees the current menu destinations including Maintenance" do
    sign_in find_or_create_platform_owner
    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect_menu_labels(%i[home assistant users entities modules settings maintenance])
  end
end
