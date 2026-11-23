# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member sign in", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  let(:customer)    { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:member)     { create(:user, :member, customer: customer, email: "lin@example.com", password: "supersecret123") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  it "renders the member auth shell and signs the user in" do
    visit "/auth/sign_in"

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_text("Welcome back.")

    fill_in "Email",    with: "lin@example.com"
    fill_in "Password", with: "supersecret123"
    click_button "Sign in"

    # The member trait gives the user the `member` role, so they should land on /:cid/member.
    expect(page).to have_current_path("/#{customer.id}/member")
  end

  it "shows an inline error when credentials are wrong" do
    visit "/auth/sign_in"
    fill_in "Email",    with: "lin@example.com"
    fill_in "Password", with: "wrong"
    click_button "Sign in"
    expect(page).to have_text(/invalid/i)
  end
end
