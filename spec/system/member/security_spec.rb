# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member security", type: :system do
  # ViewComponent::TestHelpers shadows page in :system specs; restore Capybara session.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  before { sign_in user }

  it "renders the password section linking to authenticated account editing" do
    visit "/#{customer.id}/member/security"
    expect(page).to have_text("Password")
    expect(page).to have_link("Change password",
      href: edit_user_registration_path)
  end

  it "shows the 2FA off state and a setup CTA when MFA is disabled" do
    visit "/#{customer.id}/member/security"
    expect(page).to have_text("2FA is off")
    expect(page).to have_link("Set up 2FA", href: "/#{customer.id}/member/security/mfa/setup")
  end

  it "shows the 2FA on state and a disable button when MFA is enabled" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    # Bypass the enforce_mfa! redirect filter — the page itself doesn't gate on
    # session[:mfa_verified], it just reads the user's MFA flags. Real users
    # arrive here after passing the MFA challenge; the test takes a shortcut.
    allow_any_instance_of(ApplicationController).to receive(:enforce_mfa!).and_return(nil)
    visit "/#{customer.id}/member/security"
    expect(page).to have_text("2FA is on")
    expect(page).to have_selector("summary", text: "Disable 2FA")
  end
end
