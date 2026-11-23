# frozen_string_literal: true

require "rails_helper"

# Authentication::MfasController#destroy re-auth goes through
# PasswordVerification so Devise Lockable counters apply. The shared MFA
# throttle (5 / 15 min) is a separate cap — reset it between lockout
# attempts so we can reach Devise.maximum_attempts without being 429'd first.
RSpec.describe "Authentication::Mfas", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  # Explicitly an admin: this tenant has mfa_enabled, which binds admins and
  # owners (members are opt-in), and landing redirects expect the admin surface.
  let(:user) { create(:user, :admin, :with_mfa, customer: customer, password: "password123") }

  before do
    ensure_customer_feature_module(customer, auth_module,
                                   configuration: { "mfa_enabled" => true }.to_json)
    sign_in user
    Authentication::Throttle.reset_store!
    verify_mfa_session(user)
  end

  after { Authentication::Throttle.reset_store! }

  def verify_mfa_session(otp_user)
    post mfa_session_path(customer.id), params: { otp_code: ROTP::TOTP.new(otp_user.otp_secret).now }
  end

  def disable_mfa(password: nil, otp_code: nil)
    params = {}
    params[:current_password] = password unless password.nil?
    params[:otp_code] = otp_code unless otp_code.nil?
    delete mfa_path(customer.id), params: params
  end

  describe "DELETE /:customer_id/auth/mfa — Lockable on password re-auth" do
    it "records a single successful disable and no event for rejected re-authentication" do
      expect { disable_mfa(password: "wrongpassword") }
        .not_to change { Authentication::Event.where(event: "mfa_disabled", user_id: user.id).count }

      expect { disable_mfa(password: "password123") }
        .to change { Authentication::Event.where(event: "mfa_disabled", user_id: user.id).count }.by(1)
      event = Authentication::Event.where(event: "mfa_disabled", user_id: user.id).last
      expect(event.metadata).to include(
        "actor_id" => user.id, "source" => "self_service", "outcome" => "success",
        "after" => { "required" => false, "configured" => false }
      )
    end

    it "increments failed_attempts when the disable password is wrong" do
      expect {
        disable_mfa(password: "wrongpassword")
      }.to change { user.reload.failed_attempts }.by(1)
      expect(user.otp_required_for_login).to be(true)
      expect(user.access_locked?).to be(false)
    end

    it "locks the account after Devise.maximum_attempts consecutive wrong passwords" do
      Devise.maximum_attempts.times do
        Authentication::Throttle.reset_store!
        disable_mfa(password: "wrongpassword")
      end

      expect(user.reload.access_locked?).to be(true)
      expect(user.otp_required_for_login).to be(true)
    end

    it "disables MFA when the user presents a correct password and a valid OTP" do
      disable_mfa(password: "wrongpassword")
      expect(user.reload.failed_attempts).to eq(1)

      travel 30.seconds
      disable_mfa(
        password: "password123",
        otp_code: ROTP::TOTP.new(user.reload.otp_secret).now
      )

      user.reload
      expect(user.otp_required_for_login).to be(false)
      expect(user.otp_secret).to be_nil
    end

    # A successful re-auth breaks the streak, exactly as a successful sign-in
    # does. The counter used to only ever climb, so a user who mistyped once
    # and then re-authenticated carried that attempt forward for the life of
    # the record and crept toward a lockout they had already cleared.
    it "resets failed_attempts once the user re-authenticates with a password" do
      disable_mfa(password: "wrongpassword")
      expect(user.reload.failed_attempts).to eq(1)

      travel 30.seconds
      disable_mfa(password: "password123")

      expect(user.reload.failed_attempts).to eq(0)
    end

    it "resets failed_attempts when the user re-authenticates with an OTP instead" do
      disable_mfa(password: "wrongpassword")
      expect(user.reload.failed_attempts).to eq(1)

      travel 30.seconds
      disable_mfa(otp_code: ROTP::TOTP.new(user.reload.otp_secret).now)

      expect(user.reload.failed_attempts).to eq(0)
    end

    it "leaves the counter alone when re-auth fails" do
      disable_mfa(password: "wrongpassword")
      expect(user.reload.failed_attempts).to eq(1)
      expect(user.otp_required_for_login).to be(true)
    end
  end

  # The global activatable gate (Authentication::User#active_for_authentication?
  # chains through Devise Lockable) bounces a locked account before the action
  # runs, so neither factor can strip the second factor off a locked account.
  # Asserted here because this endpoint's own re-auth has no lock check of its
  # own and would otherwise be relying on that gate silently.
  describe "DELETE /:customer_id/auth/mfa — locked account" do
    it "refuses a valid OTP and leaves MFA enabled" do
      otp = ROTP::TOTP.new(user.otp_secret).now
      user.lock_access!

      disable_mfa(otp_code: otp)

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.otp_required_for_login).to be(true)
      expect(user.otp_secret).to be_present
    end

    it "refuses a correct password and leaves MFA enabled" do
      user.lock_access!

      disable_mfa(password: "password123")

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.otp_required_for_login).to be(true)
      expect(user.otp_secret).to be_present
    end
  end
end
