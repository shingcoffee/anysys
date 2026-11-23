# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member home", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer, first_name: "Lin", last_name: "Vega") }

  before { sign_in user }

  it "renders the hero, status cards, and recent activity for a member" do
    visit "/#{customer.id}/member"

    expect(page).to have_css("[data-member-hero]")
    expect(page).to have_text(/Lin/)
    expect(page).to have_text("Profile")
    expect(page).to have_text("Security")
  end

  it "hides the Payments status card when the module is disabled" do
    visit "/#{customer.id}/member"
    expect(page).not_to have_link("View all", href: %r{/payments\z})
  end

  it "shows the Payments status card when the module is enabled" do
    enable_module!("payment", customer, name: "Payments")

    visit "/#{customer.id}/member"
    expect(page).to have_link("View all", href: "/#{customer.id}/member/payments")
  end
end
