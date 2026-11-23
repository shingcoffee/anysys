# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member (system)", type: :system do
  def page ; Capybara.current_session ; end

  include_context "as admin"

  let(:member) { create(:user, :member, customer: customer) }

  before do
    enable_module!("payment", customer, name: "Payments")
  end

  it "drills hub → modules → payments, renames to Donations, and member nav reflects it" do
    sign_in admin
    visit "/#{customer.id}/admin/settings/member"
    expect(page).to have_text("Member modules")

    row = find("h3", text: "Member modules", exact_text: true).find(:xpath, "../../..")
    within(row) { click_link "Configure" }
    expect(page).to have_current_path("/#{customer.id}/admin/settings/member/sources/modules")
    expect(page).to have_text("Payments")

    within('[data-list-filter-target="item"][data-search-text="Payments"]') do
      click_link "Display settings"
    end
    fill_in "member_settings[rows][0][label]", with: "Donations"
    click_button "Save"
    expect(page).to have_text("Surface saved.")

    visit "/auth/sign_out"
    sign_in member
    visit "/#{customer.id}/member"
    expect(page).to have_link("Donations")
  end
end
