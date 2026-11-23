# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard responsive drawer", :js, type: :system do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, customer: customer, role: :admin) }

  before do
    skip "headless Chrome not available in this environment" unless system("which google-chrome > /dev/null 2>&1 || which chromium > /dev/null 2>&1")
    sign_in admin
  end

  it "opens the drawer from the hamburger button on mobile" do
    page.current_window.resize_to(375, 812)
    visit "/#{customer.id}/admin/dashboard"
    expect(page.evaluate_script("document.querySelector('header > div > div:last-child').getBoundingClientRect().right"))
      .to be <= page.evaluate_script("window.innerWidth")
    expect(page).to have_css("aside[data-drawer-target='panel'].-translate-x-full", visible: :all)
    find("button[aria-label='Open menu']").click
    expect(page).to have_css("aside[data-drawer-target='panel'].translate-x-0")
    expect(page).to have_link("Home")
    expect(page).not_to have_link("Maintenance")
  end

  it "keeps Settings visible alongside the scrollable primary menu on tablets" do
    page.current_window.resize_to(800, 900)
    visit "/#{customer.id}/admin/dashboard"

    settings = find("nav[aria-label='Dashboard menu'] a[data-menu-item-key='settings']")
    expect(settings.evaluate_script("this.getBoundingClientRect().right"))
      .to be <= page.evaluate_script("window.innerWidth")
    expect(page).to have_css("nav[aria-label='Dashboard menu'] .overflow-x-auto", visible: :all)
  end

  it "closes the drawer when the backdrop is clicked" do
    page.current_window.resize_to(375, 812)
    visit "/#{customer.id}/admin/dashboard"
    find("button[aria-label='Open menu']").click
    expect(page).to have_css("aside[data-drawer-target='panel'].translate-x-0")
    # The backdrop is full-screen (fixed inset-0) but the open panel (max-w-340px,
    # higher z-index) covers its centre, so a coordinate click hit-tests onto the
    # panel. Dispatch a real click on the backdrop element to exercise its
    # `click->drawer#close` binding directly.
    backdrop = find("[data-drawer-target='backdrop']", visible: :all)
    page.execute_script("arguments[0].click()", backdrop)
    expect(page).to have_css("aside[data-drawer-target='panel'].-translate-x-full")
  end
end
