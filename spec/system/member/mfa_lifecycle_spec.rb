# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member MFA lifecycle", type: :system do
  # ViewComponent::TestHelpers (mixed in for type: :system in rails_helper.rb)
  # shadows RSpec::Rails::SystemExampleGroup#page with one returning a
  # Capybara::Node::Simple wrapper, which breaks `visit`. Restore the system
  # runner's session-backed page here.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, customer: customer, password: "password123") }
  let(:cid)      { customer.id }

  before do
    enable_module!("authentication", customer, name: "Authentication")
    ActionMailer::Base.deliveries.clear
  end

  it "lets a member enable MFA, sign in with it, recover via email, and sign in without it" do
    # 1. Sign in fresh; MFA off by default
    visit "/auth/sign_in"
    fill_in "Email",    with: member.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path("/#{cid}/member")

    # 2. Visit security page; see "off"
    visit "/#{cid}/member/security"
    expect(page).to have_content("2FA is off")
    click_link "Set up 2FA"

    # 3. Enable MFA — submit a fresh TOTP from the seeded otp_secret
    expect(page).to have_current_path("/#{cid}/member/security/mfa/setup")
    member.reload
    fill_in "code", with: ROTP::TOTP.new(member.otp_secret).now
    click_button "Verify and enable"
    expect(page).to have_current_path("/#{cid}/member/security")
    expect(page).to have_content("2FA is on")

    # 4. Sign out, sign back in -> MFA challenge
    Capybara.reset_sessions!
    visit "/auth/sign_in"
    fill_in "Email",    with: member.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path("/#{cid}/auth/mfa/session")

    # 5. Click "Lost your authenticator?" -> request reset
    click_link "Lost your authenticator?"
    fill_in "Email", with: member.email
    perform_enqueued_jobs { click_button "Send reset link" }
    expect(page).to have_content(/check your email/i)

    # 6. Read the email, click the link. The mailer sends a multipart message
    #    with quoted-printable encoding; pull the decoded text part so the
    #    token isn't mangled by line wraps.
    mail = ActionMailer::Base.deliveries.last
    expect(mail).not_to be_nil
    text_part = mail.text_part || mail.html_part || mail
    consume_url = text_part.body.decoded[%r{(/#{cid}/auth/mfa_recovery/consume\?token=[^"\s]+)}, 1]
    expect(consume_url).to be_present

    visit consume_url
    click_button "Disable two-factor authentication"
    expect(page).to have_current_path("/auth/sign_in")
    expect(member.reload.mfa_required?).to be(false)

    # 7. Sign in normally — no MFA challenge
    fill_in "Email",    with: member.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path("/#{cid}/member")
  end
end
