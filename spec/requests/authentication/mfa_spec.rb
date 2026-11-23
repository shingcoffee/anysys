# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::Mfa", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  # Explicitly an admin: this tenant has mfa_enabled, which binds admins and
  # owners (members are opt-in), and every landing assertion below expects the
  # admin surface. A role-less fixture would resolve to the member surface.
  let(:user) { create(:user, :admin, customer: customer, password: "password123") }

  before do
    ensure_customer_feature_module(customer, auth_module,
                                   configuration: { "mfa_enabled" => true }.to_json)
    sign_in user
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  # Posts the user's current valid TOTP to the MFA verify endpoint.
  def verify_mfa_session(otp_user)
    post mfa_session_path(customer.id), params: { otp_code: ROTP::TOTP.new(otp_user.otp_secret).now }
  end

  describe "GET /:customer_id/auth/mfa/setup" do
    it "generates OTP secret for user" do
      get mfa_setup_path(customer.id)
      expect(user.reload.otp_secret).to be_present
    end

    it "renders QR code" do
      get mfa_setup_path(customer.id)
      expect(response.body).to include("Set up 2FA")
    end
  end

  describe "POST /:customer_id/auth/mfa/confirm_setup" do
    before { user.generate_otp_secret! }

    it "enables MFA with valid code" do
      totp = ROTP::TOTP.new(user.otp_secret)
      post mfa_setup_path(customer.id), params: { otp_code: totp.now }
      expect(user.reload.otp_required_for_login).to be true
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "rejects invalid code" do
      post mfa_setup_path(customer.id), params: { otp_code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.otp_required_for_login).to be false
    end
  end

  describe "GET /:customer_id/auth/mfa/verify" do
    context "when the user has MFA configured" do
      let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

      it "renders verification form" do
        get mfa_session_path(customer.id)
        expect(response.body).to include("Two-factor verification")
        expect(response.body).to include("placeholder=\"000000\"")
        expect(response.body).to include('data-turbo="false"')
      end

      it "hides MFA recovery from admins (recovery mailer only serves members)" do
        admin = create(:user, :admin, :with_mfa, customer: customer, password: "password123")
        sign_in admin
        get mfa_session_path(customer.id)
        expect(response.body).not_to include("Lost your authenticator?")
      end

      it "shows MFA recovery to members" do
        member = create(:user, :member, :with_mfa, customer: customer, password: "password123")
        sign_in member
        get mfa_session_path(customer.id)
        expect(response.body).to include("Lost your authenticator?")
      end
    end

    context "when the user has no MFA configured" do
      it "redirects to the dashboard rather than presenting a verification form" do
        # The verify page is only meaningful when the user actually has a
        # TOTP secret. Without one, prompting for a code is nonsense and
        # would let a not-yet-set-up user wedge themselves into a 422 loop.
        get mfa_session_path(customer.id)
        expect(response).to redirect_to(admin_assistant_path(customer.id))
      end
    end
  end

  describe "POST /:customer_id/auth/mfa/authenticate" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    it "verifies valid OTP and sets session flag" do
      verify_mfa_session(user)
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "rejects invalid OTP" do
      post mfa_session_path(customer.id), params: { otp_code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /:customer_id/auth/mfa/disable" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    # Disabling MFA implies an authenticated, MFA-verified session: the
    # enforce_mfa filter would otherwise (correctly) bounce the request to
    # the verify page, so these specs simulate a verified session.
    before do
      verify_mfa_session(user)
    end

    it "disables MFA when the user re-authenticates with their password" do
      delete mfa_path(customer.id), params: { current_password: "password123" }
      expect(user.reload.otp_required_for_login).to be false
      expect(user.otp_secret).to be_nil
    end

    it "redirects to the dashboard after a successful disable" do
      delete mfa_path(customer.id), params: { current_password: "password123" }
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "refuses to disable MFA without re-authentication" do
      # Disabling 2FA requires fresh proof of identity (current password or
      # a valid OTP) so a stolen/fixed session alone cannot strip the
      # second factor in a single click.
      delete mfa_path(customer.id)
      expect(user.reload.otp_required_for_login).to be true
      expect(user.otp_secret).to be_present
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "is blocked when MFA has not been verified yet" do
      # Reset the session to an unverified state by signing the user out
      # and back in without verifying.
      delete destroy_user_session_path
      sign_in user

      delete mfa_path(customer.id)
      expect(response).to redirect_to(mfa_session_path(customer.id))
      expect(user.reload.otp_required_for_login).to be true
    end
  end

  describe "DELETE /:customer_id/auth/mfa/disable — throttle" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    # A valid verify resets the shared mfa:<id> bucket, so each example starts
    # from a clean counter.
    before { verify_mfa_session(user) }

    def fail_disable_attempt
      delete mfa_path(customer.id), params: { current_password: "wrongpassword" }
    end

    it "records a failed re-auth attempt and keeps MFA enabled" do
      fail_disable_attempt
      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.reload.otp_required_for_login).to be true
    end

    it "throttles the disable endpoint after 5 failed re-auth attempts (fails closed)" do
      5.times { fail_disable_attempt }
      # 6th attempt is refused even though the password is now correct.
      delete mfa_path(customer.id), params: { current_password: "password123" }
      expect(flash[:alert]).to eq(I18n.t("auth.flash.mfa.throttled"))
      expect(user.reload.otp_required_for_login).to be true
    end

    it "records a throttled audit event once the limit is exceeded" do
      5.times { fail_disable_attempt }
      expect {
        delete mfa_path(customer.id), params: { current_password: "password123" }
      }.to change { Authentication::Event.where(event: "throttled", user_id: user.id).count }.by(1)
    end

    it "shares the throttle bucket with the MFA verify flow" do
      # 5 failed verify attempts trip the shared mfa:<id> bucket, so the disable
      # endpoint is throttled too even though it saw no failures of its own.
      5.times { post mfa_session_path(customer.id), params: { otp_code: "000000" } }
      delete mfa_path(customer.id), params: { current_password: "password123" }
      expect(flash[:alert]).to eq(I18n.t("auth.flash.mfa.throttled"))
      expect(user.reload.otp_required_for_login).to be true
    end
  end

  describe "DELETE /:customer_id/auth/mfa/disable — member routing" do
    let(:member_user) { create(:user, :member, :with_mfa, customer: customer, password: "password123") }

    before do
      sign_in member_user
      verify_mfa_session(member_user)
    end

    it "redirects a member to the member dashboard after disabling MFA" do
      delete mfa_path(customer.id), params: { current_password: "password123" }
      expect(member_user.reload.otp_required_for_login).to be false
      expect(response).to redirect_to(member_dashboard_path(customer.id))
    end
  end

  # ==========================================================================
  # MfaSessionsController — unauthenticated redirect and member routing
  # ==========================================================================

  describe "MfaSessionsController — unauthenticated user" do
    before { sign_out :user }

    it "redirects to sign-in when not signed in" do
      get mfa_session_path(customer.id)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "MfaSessionsController — post_verification_path for members" do
    let(:member_user) { create(:user, :member, :with_mfa, customer: customer, password: "password123") }

    before { sign_in member_user }

    it "redirects a member to the member dashboard after MFA verification" do
      verify_mfa_session(member_user)
      expect(response).to redirect_to(member_dashboard_path(customer.id))
    end

    it "redirects a member to the member dashboard when already verified" do
      # Simulate already-verified state: session[:mfa_verified] = true
      verify_mfa_session(member_user)
      # Now visit the MFA page again — should redirect to member dashboard
      get mfa_session_path(customer.id)
      expect(response).to redirect_to(member_dashboard_path(customer.id))
    end
  end

  describe "MfaSessionsController — safe_stored_location" do
    let(:user_with_mfa) { create(:user, :admin, :with_mfa, customer: customer, password: "password123") }

    before { sign_in user_with_mfa }

    it "falls back to post_verification_path when no stored location is set" do
      verify_mfa_session(user_with_mfa)
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end
  end

  # ==========================================================================
  # MFA enforcement (regression: signed-in mfa_required users must verify
  # before reaching any other admin URL)
  # ==========================================================================
  describe "enforcement on protected pages" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    context "when mfa_verified flag is not set" do
      before do
        sign_in user
        # Simulate the post-sign-in state: signed in, not yet OTP-verified
        # (sign_in helper doesn't go through SessionsController#create)
      end

      it "blocks access to the admin dashboard and redirects to MFA verify" do
        get admin_dashboard_path(customer.id)
        expect(response).to redirect_to(mfa_session_path(customer.id))
      end

      it "permits access to the MFA verify page itself" do
        get mfa_session_path(customer.id)
        expect(response).to have_http_status(:success)
      end

      it "permits sign-out without MFA verification" do
        delete destroy_user_session_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "after successful MFA verification" do
      before do
        sign_in user
        verify_mfa_session(user)
      end

      it "permits access to the admin dashboard" do
        get admin_dashboard_path(customer.id)
        expect(response).to have_http_status(:success)
      end
    end
  end

  # ==========================================================================
  # Audit ledger — mfa_verified / mfa_failed events
  # ==========================================================================
  describe "audit events on MFA verification" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    it "records an mfa_verified event on success" do
      expect { verify_mfa_session(user) }
        .to change { Authentication::Event.where(event: "mfa_verified", user_id: user.id).count }.by(1)
    end

    it "records an mfa_failed event on an invalid code" do
      expect {
        post mfa_session_path(customer.id), params: { otp_code: "000000" }
      }.to change { Authentication::Event.where(event: "mfa_failed", user_id: user.id).count }.by(1)
    end
  end

  # ==========================================================================
  # B2 — MFA verify throttle (5 failed attempts / 15 min per user)
  # ==========================================================================
  describe "POST /:customer_id/auth/mfa/authenticate — throttle" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    def fail_mfa_attempt
      post mfa_session_path(customer.id), params: { otp_code: "000000" }
    end

    it "allows up to the 5th failed attempt without throttling" do
      4.times { fail_mfa_attempt }
      fail_mfa_attempt
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "throttles the 6th failed attempt within the window with a 429" do
      5.times { fail_mfa_attempt }
      fail_mfa_attempt
      expect(response).to have_http_status(:too_many_requests)
    end

    it "renders the throttled flash message" do
      5.times { fail_mfa_attempt }
      fail_mfa_attempt
      expect(response.body).to include(I18n.t("auth.flash.mfa.throttled"))
    end

    it "records a throttled audit event once the limit is exceeded" do
      5.times { fail_mfa_attempt }
      expect { fail_mfa_attempt }
        .to change { Authentication::Event.where(event: "throttled", user_id: user.id).count }.by(1)
    end

    it "does not verify a correct code once throttled (fails closed)" do
      5.times { fail_mfa_attempt }
      verify_mfa_session(user)
      expect(response).to have_http_status(:too_many_requests)
      expect(session[:mfa_verified]).not_to be true
    end

    it "clears the throttle counter on a successful verification" do
      3.times { fail_mfa_attempt }
      verify_mfa_session(user)
      expect(response).to redirect_to(admin_assistant_path(customer.id))

      # The counter was cleared by the success, so 4 more failures (< limit
      # of 5) should NOT trip the throttle — proves #clear actually ran.
      sign_out user
      sign_in user
      4.times { fail_mfa_attempt }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "scopes the throttle per user — a second user's attempts are unaffected" do
      5.times { fail_mfa_attempt }

      other_user = create(:user, :with_mfa, :admin, customer: customer, password: "password123")
      sign_out user
      sign_in other_user

      post mfa_session_path(customer.id), params: { otp_code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
