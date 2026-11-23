# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Settings — Member Entities", type: :system do
  def page ; Capybara.current_session ; end

  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  it "shows a freshly created Entity under Record pages" do
    Entity.create!(customer_id: customer.id, name: "Course")

    sign_in admin
    visit "/#{customer.id}/admin/settings/member"
    expect(page).to have_text("Record pages")

    row = find("h3", text: "Record pages", exact_text: true).find(:xpath, "../../..")
    within(row) { click_link "Configure" }
    expect(page).to have_current_path("/#{customer.id}/admin/settings/member/sources/entities")
    expect(page).to have_text("Course")
  end
end
