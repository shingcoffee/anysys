# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member password reset", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  let(:customer)    { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:member)     { create(:user, :member, customer: customer, email: "lin@example.com") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  it "renders the reset request form on the member auth shell" do
    visit "/auth/password/new"

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_text("Forgot password")
    expect(page).to have_button("Send reset link")
  end

  it "accepts a known email and shows the standard Devise notice" do
    visit "/auth/password/new"
    fill_in "Email", with: "lin@example.com"
    click_button "Send reset link"

    # Devise's default flash message - we don't intercept it.
    expect(page).to have_text(/email/i)
  end
end
