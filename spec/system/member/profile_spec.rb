# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member profile", type: :system do
  # ViewComponent::TestHelpers shadows page in :system specs; restore Capybara session.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer, first_name: "Lin", last_name: "Vega") }

  before { sign_in user }

  it "renders the show page with the user's data" do
    visit "/#{customer.id}/member/profile"
    expect(page).to have_text("Lin Vega")
    expect(page).to have_text(user.email)
    expect(page).to have_link("Edit profile")
  end

  it "updates first and last name from the edit form" do
    visit "/#{customer.id}/member/profile/edit"
    fill_in "First name", with: "Linnea"
    click_button "Save changes"

    expect(page).to have_current_path("/#{customer.id}/member/profile")
    expect(page).to have_text("Profile updated.")
    expect(page).to have_text("Linnea Vega")
  end

  it "shows validation errors when fields are blank" do
    visit "/#{customer.id}/member/profile/edit"
    fill_in "First name", with: ""
    click_button "Save changes"

    expect(page).to have_text(/can't be blank/i)
  end
end
