# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member sign up", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  let(:customer)    { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before do
    # Customer#after_create auto-provisions the authentication assignment.
    # Flip it on with allow_registration so /:cid/auth/sign_up is reachable.
    ensure_customer_feature_module(customer, auth_module,
                                   status: :active,
                                   configuration: { "allow_registration" => true }.to_json)
  end

  it "creates an unconfirmed user and redirects to sign-in pending email confirmation" do
    visit "/#{customer.id}/auth/sign_up"

    expect(page).to have_css("[data-shell='member-auth']")
    expect(page).to have_text("Create your account.")

    fill_in "First name", with: "Lin"
    fill_in "Last name",  with: "Vega"
    fill_in "Email",      with: "lin@example.com"
    fill_in "Password",   with: "supersecret123"
    fill_in "Confirm password", with: "supersecret123"
    click_button "Create account"

    # After Task 9: sign-up no longer auto-signs the user in. Instead, it
    # redirects to sign-in pending email confirmation.
    expect(page).to have_current_path("/auth/sign_in")
    expect(page).to have_text(/confirmation link/i)

    user = Authentication::User.find_by(email: "lin@example.com", customer_id: customer.id)
    expect(user).to be_present
    expect(user.member?).to be true
    expect(user.confirmed_at).to be_nil

    # Exercise the confirmation-then-sign-in flow: mark the user confirmed
    # (cleaner than parsing email markup), then sign in successfully.
    user.update!(confirmed_at: Time.current)
    fill_in "Email",    with: "lin@example.com"
    fill_in "Password", with: "supersecret123"
    click_button "Sign in"

    expect(page).to have_current_path("/#{customer.id}/member")
    expect(page).to have_text(/Good (morning|afternoon|evening), Lin\./)
  end
end
