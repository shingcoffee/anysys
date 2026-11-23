require "rails_helper"

RSpec.describe "Admin settings — User Authentication", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  let!(:customer) { create(:customer) }
  let!(:admin)    { create(:user, :admin, customer: customer, password: "password123") }

  it "admin can toggle Sign up and Forget password from their dedicated settings entries and the public surfaces respond" do
    visit "/auth/sign_in"
    fill_in "Email", with: admin.email
    fill_in "Password", with: "password123"
    click_button "Sign in"

    # Sign up settings entry
    visit "/#{customer.id}/admin/settings/modules/authentication/sign_up"
    expect(page).to have_css("h1", text: "Member registration", exact_text: true)
    select "Enabled", from: "setting_enabled"
    click_button "Save"

    # Forget password settings entry
    visit "/#{customer.id}/admin/settings/modules/authentication/forget_password"
    expect(page).to have_css("h1", text: "Password reset", exact_text: true)
    select "Disabled", from: "setting_enabled"
    click_button "Save"

    fm = FeatureModules::Module.find_by!(key: "authentication")
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    config = cfm.configuration_json
    expect(config["allow_registration"]).to   eq(true)
    expect(config["allow_password_reset"]).to eq(false)

    # Sign out via direct DELETE so we don't depend on a particular UI element
    page.driver.submit :delete, "/auth/sign_out", {}

    visit "/#{customer.id}/auth/sign_up"
    expect(page).to have_content("Create your account")

    visit "/auth/password/new"
    expect(page).to have_button("Send reset link")
    expect(page).not_to have_content("Password reset is currently disabled")
  end
end
