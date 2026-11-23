# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard inline search", :js, type: :system do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, customer: customer, role: :admin) }

  before do
    sign_in admin
  end

  def open_search
    search = find("[data-controller='inline-search']", visible: true)
    # A click before Stimulus connects is inert. Retry that interaction only
    # while this responsive variant's trigger is still visible, and wait for
    # a positively visible input (a negative hidden selector is vacuous).
    search.synchronize(errors: [Capybara::ElementNotFound]) do
      trigger = "[data-inline-search-target='trigger']"
      search.find(trigger, wait: 0).click if search.has_css?(trigger, wait: 0)
      search.find("[data-inline-search-target='expanded']:not(.hidden) [data-inline-search-target='input']", wait: 0)
    end
  end

  it "expands, shows live results for a matching query, and navigates on click" do
    checkout_page = create(:page, customer: customer, name: "Checkout Form")
    visit "/#{customer.id}/admin/dashboard"
    input = open_search
    input.set("checkout")
    within(input.find(:xpath, "ancestor::*[@data-controller='inline-search']")) do
      expect(page).to have_text(/pages/i)
      expect(page).to have_link("Checkout Form")
      click_link "Checkout Form"
    end
    expect(page).to have_current_path("/#{customer.id}/admin/maintenance/pages/#{checkout_page.id}", ignore_query: true)
  end

  it "collapses the search on Escape" do
    visit "/#{customer.id}/admin/dashboard"
    input = open_search
    search = input.find(:xpath, "ancestor::*[@data-controller='inline-search']")
    input.send_keys(:escape)
    expect(search).to have_css("[data-inline-search-target='expanded'].hidden", visible: :all)
    expect(search).to have_css("[data-inline-search-target='trigger']", visible: true)
  end
end
