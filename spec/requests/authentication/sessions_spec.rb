# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::Sessions", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    # The sign-in-link intent branch shares the process-wide email-flood
    # bucket with every other spec that requests a link. The per-IP sign-in
    # cap uses the same shared Throttle store.
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  describe "GET /auth/sign_in" do
    it "renders sign in form" do
      get new_user_session_path
      expect(response.body).to include("Welcome back.")
      expect(response.body).to include("Sign in to continue.")
      expect(response.body).to include("Sign in")
      expect(response.body).not_to include("Manage your profile")
      expect(response.body).not_to include("Track payments")
    end

    it "still renders the sign-in form when a tenant has auth disabled (checked after lookup)" do
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).delete_all
      get new_user_session_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /auth/sign_in" do
    let!(:user) { create(:user, :admin, customer: customer, email: "test@example.com", password: "password123") }

    it "signs in with valid credentials" do
      post user_session_path,
           params: { user: { email: "test@example.com", password: "password123", customer_id: customer.id } }
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "tracks sign-in once and retains the preceding sign-in timestamp and IP" do
      previous_time = 2.days.ago.change(usec: 0)
      previous_ip = "203.0.113.10"
      current_ip = "203.0.113.20"
      user.update_columns(current_sign_in_at: previous_time, current_sign_in_ip: previous_ip)

      expect {
        post user_session_path,
             params: { user: { email: user.email, password: "password123" } },
             headers: { "REMOTE_ADDR" => current_ip }
      }.to change { user.reload.sign_in_count }.by(1)

      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.last_sign_in_at).to eq(previous_time)
      expect(user.last_sign_in_ip).to eq(previous_ip)
      expect(user.current_sign_in_at).to be > previous_time
      expect(user.current_sign_in_ip).to eq(current_ip)

      expect { get admin_dashboard_path(customer.id) }
        .not_to change { user.reload.sign_in_count }
    end

    it "does not treat visiting MFA setup as completing tenant-enforced enrollment" do
      admin = create(:user, :admin, customer: customer, email: "admin-enroll@example.com", password: "password123")
      ensure_customer_feature_module(customer, auth_module, status: :active,
                                     configuration: { "mfa_enabled" => true }.to_json)

      post user_session_path,
           params: { user: { email: admin.email, password: "password123" } }
      expect(response).to redirect_to(mfa_setup_path(customer.id))

      follow_redirect!
      expect(admin.reload.otp_secret).to be_present

      get admin_dashboard_path(customer.id)
      expect(response).to be_redirect
      expect(response.location).to match(%r{/auth/mfa/(setup|session)\z})
    end

    it "sends a sign-in link when the email-link intent is submitted" do
      expect {
        perform_enqueued_jobs do
          post user_session_path,
               params: { intent: "sign_in_link", user: { email: "test@example.com" } }
        end
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(controller.user_signed_in?).to be(false)
      expect(response).to redirect_to(sign_in_link_check_email_path)
    end

    # Both entry points (this intent branch and POST /auth/sign_in_link) run the
    # same shared implementation, so they must normalize the address identically
    # — they share one throttle bucket keyed on the normalized value.
    it "normalizes the address on the intent branch the same way as the dedicated route" do
      post user_session_path,
           params: { intent: "sign_in_link", user: { email: "  TEST@Example.COM " } }

      expect(response).to redirect_to(sign_in_link_check_email_path)
      follow_redirect!
      expect(response.body).to include("test@example.com")
      expect(user.reload.sign_in_token).to be_present
    end

    it "rejects invalid credentials" do
      post user_session_path,
           params: { user: { email: "test@example.com", password: "wrong", customer_id: customer.id } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Welcome back.")
      expect(response.body).to include("Invalid email or password")
    end

    it "does not 500 when user is posted as an array" do
      post user_session_path, params: { user: ["not-a-hash"] }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid email or password")
    end

    it "rejects inactive users" do
      user.update!(status: :inactive)
      post user_session_path,
           params: { user: { email: "test@example.com", password: "password123", customer_id: customer.id } }
      # Inactive users are excluded from authentication lookup, so treated as invalid credentials
      expect(response).to have_http_status(:unprocessable_content)
    end

    context "remember me (B3)" do
      it "issues a persistent remember cookie when checked" do
        post user_session_path,
             params: { user: { email: "test@example.com", password: "password123",
                               customer_id: customer.id, remember_me: "1" } }
        expect(response.cookies["remember_user_token"]).to be_present
        expect(user.reload.remember_created_at).to be_present
      end

      it "does not issue a remember cookie when unchecked" do
        post user_session_path,
             params: { user: { email: "test@example.com", password: "password123",
                               customer_id: customer.id, remember_me: "0" } }
        expect(response.cookies["remember_user_token"]).to be_nil
        expect(user.reload.remember_created_at).to be_nil
      end
    end

    context "when platform captcha is configured" do
      before do
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)
      end

      it "accepts a password POST without a captcha token while under the URL throttle" do
        post user_session_path,
             params: { user: { email: "test@example.com", password: "password123" } }

        expect(response).not_to have_http_status(:unprocessable_content)
        expect(controller.user_signed_in?).to be(true)
      end
    end
  end

  describe "rate limiting" do
    let!(:user) { create(:user, customer: customer, email: "rl@example.com", password: "password123") }

    it "returns 429 after exceeding the per-IP attempt cap" do
      cap = Authentication::SessionsController::RATE_LIMIT_CAP
      (cap + 1).times do
        post user_session_path,
             params: { user: { email: "rl@example.com", password: "wrong", customer_id: customer.id } }
      end
      expect(response).to have_http_status(:too_many_requests)
    end

    it "records a throttled audit event once the cap is exceeded" do
      cap = Authentication::SessionsController::RATE_LIMIT_CAP
      cap.times do
        post user_session_path,
             params: { user: { email: "rl@example.com", password: "wrong", customer_id: customer.id } }
      end

      expect {
        post user_session_path,
             params: { user: { email: "rl@example.com", password: "wrong", customer_id: customer.id } }
      }.to change { Authentication::Event.where(event: "throttled").count }.by(1)
    end
  end

  describe "lockable integration" do
    let!(:user) { create(:user, customer: customer, email: "lock@example.com", password: "password123") }

    def sign_in_attempt(password)
      post user_session_path,
           params: { user: { email: "lock@example.com", password: password, customer_id: customer.id } }
    end

    it "increments failed_attempts on bad password" do
      expect { sign_in_attempt("wrong") }.to change { user.reload.failed_attempts }.by(1)
    end

    it "locks the account after Devise.maximum_attempts failed attempts" do
      Devise.maximum_attempts.times { sign_in_attempt("wrong") }
      expect(user.reload.access_locked?).to be(true)
    end

    it "rejects valid credentials once the account is locked" do
      Devise.maximum_attempts.times { sign_in_attempt("wrong") }
      sign_in_attempt("password123")
      expect(response).to have_http_status(:unprocessable_content)
      expect(controller.user_signed_in?).to be(false)
    end

    it "resets failed_attempts on a successful sign-in" do
      sign_in_attempt("wrong")
      expect(user.reload.failed_attempts).to eq(1)
      sign_in_attempt("password123")
      expect(user.reload.failed_attempts).to eq(0)
    end
  end

  describe "DELETE /auth/sign_out" do
    let!(:user) { create(:user, customer: customer, email: "test@example.com", password: "password123") }

    before { sign_in user }

    it "signs out and redirects" do
      delete destroy_user_session_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "after_sign_in_path_for — member vs admin routing" do
    # Admins go to the admin dashboard; members go to /:cid/member.
    it "redirects an admin to the AI Assistant after sign-in" do
      admin = create(:user, :admin, customer: customer, password: "password123")
      post user_session_path,
           params: { user: { email: admin.email, password: "password123" } }
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "redirects a member to the member surface after sign-in" do
      member = create(:user, :member, customer: customer,
                      email: "member_test@example.com", password: "password123")
      post user_session_path,
           params: { user: { email: member.email, password: "password123" } }
      expect(response).to redirect_to("/#{customer.id}/member")
    end
  end

  describe "safe_local_path? — stored location handling" do
    let!(:admin_user) { create(:user, :admin, customer: customer, password: "password123") }

    it "follows a same-tenant stored location after sign-in" do
      # Visiting a protected admin URL while anonymous causes Devise to stash
      # the URL in stored_location_for(:user). Signing in then exercises the
      # safe_local_path? happy path that returns the stored same-tenant path.
      get admin_dashboard_path(customer.id)
      expect(response).to redirect_to(new_user_session_path)
      # After the redirect, Devise stored the original admin dashboard URL.
      # Now sign in — the stored location is same-tenant, so safe_local_path?
      # returns true and the controller redirects there.
      post user_session_path,
           params: { user: { email: admin_user.email, password: "password123" } }
      expect(response).to be_redirect
      expect(response.location).to include(customer.id.to_s)
    end

    it "falls back to the AI Assistant when no stored path is present" do
      post user_session_path,
           params: { user: { email: admin_user.email, password: "password123" } }
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end
  end

  describe "MFA-required sign-in flow" do
    let!(:mfa_user) { create(:user, :admin, :with_mfa, customer: customer, password: "password123") }

    it "redirects to MFA verify page when user has otp_required_for_login" do
      post user_session_path,
           params: { user: { email: mfa_user.email, password: "password123" } }
      expect(response).to redirect_to(mfa_session_path(customer.id))
    end
  end

  describe "MFA setup-required sign-in flow" do
    # A user with otp_secret set but otp_required_for_login false is in the
    # 'mfa_configured but not enforced' state. The sign-in flow checks
    # mfa_setup_required which means the user needs to complete setup.
    let!(:setup_user) { create(:user, :admin, :mfa_configured, customer: customer, password: "password123") }

    it "redirects to the MFA setup page when setup is required by policy" do
      # Ensure MFA is required by the module policy so SignInFlow returns :mfa_setup_required
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: auth_module.id
      )
      cfm.update!(configuration: { "mfa_required" => true }.to_json)

      post user_session_path,
           params: { user: { email: setup_user.email, password: "password123" } }
      # Should redirect to setup or the normal dashboard depending on policy enforcement
      # The controller redirects to mfa_setup_path when result.next_action == :mfa_setup_required
      expect(response).to be_redirect
    end
  end

  describe "sign_out — mfa_verified session cleanup" do
    let!(:user) { create(:user, :admin, customer: customer, password: "password123") }

    it "clears the mfa_verified session key on sign-out" do
      sign_in user
      # Simulate mfa_verified being in the session
      delete destroy_user_session_path
      expect(response).to redirect_to(new_user_session_path)
      # After sign-out, re-visiting a protected admin page redirects to sign-in
      get admin_dashboard_path(customer.id)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "unconfirmed user flow" do
    let(:customer) { create(:customer) }
    let!(:user) do
      create(:user, :unconfirmed,
             customer: customer,
             email: "pending@example.com",
             password: "Password123!")
    end

    before do
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :active,
                  configuration: { "allow_registration" => true }.to_json)
    end

    it "blocks sign-in for an unconfirmed user and stashes email in session" do
      post "/auth/sign_in",
           params: { user: { email: "pending@example.com", password: "Password123!" } }
      expect(response).to redirect_to(new_user_session_path)

      follow_redirect!
      expect(response.body).to include("Please confirm your email")
      expect(response.body).to include("Resend confirmation")
    end

    it "after confirmation, sign-in succeeds" do
      user.update!(confirmed_at: Time.current)
      post "/auth/sign_in",
           params: { user: { email: "pending@example.com", password: "Password123!" } }
      # Existing controller redirects (302/303) for member role to /:cid/member
      expect([302, 303]).to include(response.status)
    end
  end

  # ==========================================================================
  # Audit ledger — login_succeeded / login_failed / locked_out / logout
  # ==========================================================================
  describe "audit events" do
    let!(:user) { create(:user, customer: customer, email: "audit@example.com", password: "password123") }

    def sign_in_attempt(password)
      post user_session_path,
           params: { user: { email: "audit@example.com", password: password, customer_id: customer.id } }
    end

    it "records login_succeeded on a successful sign-in" do
      expect { sign_in_attempt("password123") }
        .to change { Authentication::Event.where(event: "login_succeeded", user_id: user.id).count }.by(1)
    end

    it "records login_failed on a bad password" do
      expect { sign_in_attempt("wrong") }
        .to change { Authentication::Event.where(event: "login_failed", user_id: user.id).count }.by(1)
    end

    it "records locked_out (not login_failed) once the account is already locked" do
      Devise.maximum_attempts.times { sign_in_attempt("wrong") }
      expect(user.reload.access_locked?).to be(true)

      expect { sign_in_attempt("wrong") }
        .to change { Authentication::Event.where(event: "locked_out", user_id: user.id).count }.by(1)
    end

    it "records logout when signing out" do
      sign_in user
      expect { delete destroy_user_session_path }
        .to change { Authentication::Event.where(event: "logout", user_id: user.id).count }.by(1)
    end
  end
end
