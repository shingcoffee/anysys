# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::Passwords", type: :request do
  # Devise mail is enqueued; deliver it so examples can read the mailbox.
  around { |example| perform_enqueued_jobs { example.run } }

  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:user) { create(:user, customer: customer, email: "pwd@example.com", password: "password123") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    Authentication::Throttle.reset_store!
  end

  describe "GET /auth/password/new" do
    it "renders the reset password submit button copy" do
      get new_user_password_path
      expect(response.body).to include("Send reset link")
    end

    it "still renders the form when auth module is disabled (checked after lookup)" do
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).delete_all
      get new_user_password_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /auth/password" do
    it "enqueues the reset mailer for a known email" do
      expect {
        post user_password_path,
             params: { user: { email: "pwd@example.com" } }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "does not 500 when user is posted as an array" do
      expect {
        post user_password_path, params: { user: ["not-a-hash"] }
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders a global reset link in the mailer body" do
      ActionMailer::Base.deliveries.clear
      post user_password_path,
           params: { user: { email: "pwd@example.com" } }

      mail = ActionMailer::Base.deliveries.last
      body = [mail.html_part, mail.text_part].compact.map { |part| part.body.to_s }.join
      expect(body).to include("/auth/password/edit")
      expect(body).to include("reset_password_token=")
    end

    it "redirects on unknown email (paranoid mode: do not leak existence)" do
      post user_password_path,
           params: { user: { email: "nobody@example.com" } }
      expect(response).to redirect_to(new_user_session_path)
    end

    it "does not enqueue mail for an unknown email" do
      ActionMailer::Base.deliveries.clear
      post user_password_path,
           params: { user: { email: "nobody@example.com" } }
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    context "when platform captcha is configured" do
      before do
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)
      end

      it "accepts a POST without a captcha token while under the URL throttle" do
        ActionMailer::Base.deliveries.clear
        post user_password_path, params: { user: { email: "pwd@example.com" } }

        expect(response).not_to have_http_status(:unprocessable_content)
        expect(ActionMailer::Base.deliveries).not_to be_empty
      end
    end
  end

  describe "GET /auth/password/edit" do
    it "renders with a valid reset token" do
      raw_token = user.send(:set_reset_password_token)
      get edit_user_password_path, params: { reset_password_token: raw_token }
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /auth/password" do
    let(:raw_token) { user.send(:set_reset_password_token) }

    def patch_reset_password(token)
      patch user_password_path, params: {
        user: {
          reset_password_token: token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }
      }
    end

    it "updates the password and redirects per after_resetting_password_path_for" do
      patch_reset_password(raw_token)
      user.reload
      expect(user.valid_password?("newpassword123")).to be(true)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "re-renders with 422 when the reset token is invalid" do
      patch_reset_password("not-a-real-token")
      expect(response).to have_http_status(422)
    end

    it "does not sign the user in after a successful password reset" do
      patch_reset_password(raw_token)
      expect(controller.user_signed_in?).to be(false)
    end

    it "signs the user in after reset when sign_in_after_reset_password? is true" do
      allow_any_instance_of(Authentication::PasswordsController)
        .to receive(:sign_in_after_reset_password?).and_return(true)

      patch_reset_password(raw_token)
      expect(controller.user_signed_in?).to be(true)
    end

    it "does NOT sign the user in after reset when sign_in_after_reset_password? is false" do
      allow_any_instance_of(Authentication::PasswordsController)
        .to receive(:sign_in_after_reset_password?).and_return(false)

      patch_reset_password(raw_token)
      expect(controller.user_signed_in?).to be(false)
    end
  end

  describe "toggle gating" do
    let(:customer) { create(:customer) }
    let!(:user) { create(:user, customer: customer, email: "user@example.com") }

    def set_reset(enabled)
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :active,
                  configuration: { "allow_password_reset" => enabled }.to_json)
    end

    context "when allow_password_reset is false" do
      before { set_reset(false) }

      it "GET /password/new still renders the form (no tenant to show a disabled page)" do
        get "/auth/password/new"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Send reset link")
        expect(response.body).not_to include("Password reset is currently disabled")
      end

      it "POST /password sends no email and still redirects (paranoid, no leak)" do
        expect {
          post "/auth/password", params: { user: { email: user.email } }
        }.not_to change { ActionMailer::Base.deliveries.size }
        expect(response).to redirect_to(new_user_session_path)
      end

      # The consume side is gated too, not just the request side. A token minted
      # while reset was enabled otherwise stayed redeemable for its whole 6-hour
      # window after an admin turned the toggle off, which would make disabling
      # useless as an incident-response control.
      it "GET /password/edit?token=… refuses a token whose tenant has reset disabled" do
        token = user.send(:set_reset_password_token)
        get "/auth/password/edit", params: { reset_password_token: token }
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include("Password reset is currently disabled")
      end

      it "PATCH /password refuses to consume a token whose tenant has reset disabled" do
        token = user.send(:set_reset_password_token)
        patch "/auth/password",
              params: { user: { reset_password_token: token,
                                password: "NewPassword123!",
                                password_confirmation: "NewPassword123!" } }
        expect(response).to have_http_status(:forbidden)
        expect(user.reload.valid_password?("NewPassword123!")).to be(false)
      end

      context "with conflicting query and user reset tokens" do
        let(:allowed_user) do
          allowed_customer = create(:customer)
          ensure_customer_feature_module(allowed_customer, auth_module, status: :active,
                                         configuration: { "allow_password_reset" => true }.to_json)
          create(:user, customer: allowed_customer)
        end
        let(:disabled_token) { user.send(:set_reset_password_token) }
        let(:allowed_token) { allowed_user.send(:set_reset_password_token) }

        it "does not let an unknown query token bypass the disabled payload token's gate" do
          token = disabled_token
          digest = user.reload.reset_password_token

          patch user_password_path(reset_password_token: "unknown-query-token"), params: {
            user: { reset_password_token: token,
                    password: "NewPassword123!", password_confirmation: "NewPassword123!" }
          }

          expect(response).to have_http_status(:forbidden)
          expect(user.reload.reset_password_token).to eq(digest)
          expect(user.valid_password?("NewPassword123!")).to be(false)
        end

        it "does not let another tenant's allowed query token authorize a disabled payload token" do
          token = disabled_token
          digest = user.reload.reset_password_token

          patch user_password_path(reset_password_token: allowed_token), params: {
            user: { reset_password_token: token,
                    password: "NewPassword123!", password_confirmation: "NewPassword123!" }
          }

          expect(response).to have_http_status(:forbidden)
          expect(user.reload.reset_password_token).to eq(digest)
          expect(user.valid_password?("NewPassword123!")).to be(false)
          expect(allowed_user.reload.valid_password?("NewPassword123!")).to be(false)
        end

        it "checks the allowed payload token on update even when the query token is disabled" do
          patch user_password_path(reset_password_token: disabled_token), params: {
            user: { reset_password_token: allowed_token,
                    password: "NewPassword123!", password_confirmation: "NewPassword123!" }
          }

          expect(response).to redirect_to(new_user_session_path)
          expect(allowed_user.reload.valid_password?("NewPassword123!")).to be(true)
          expect(user.reload.valid_password?("NewPassword123!")).to be(false)
        end

        it "checks the disabled query token on edit even when the payload token is allowed" do
          get edit_user_password_path, params: {
            reset_password_token: disabled_token, user: { reset_password_token: allowed_token }
          }

          expect(response).to have_http_status(:forbidden)
        end

        it "renders the allowed query token on edit despite a disabled payload token" do
          token = allowed_token
          get edit_user_password_path, params: {
            reset_password_token: token, user: { reset_password_token: disabled_token }
          }

          expect(response).to have_http_status(:ok)
          expect(controller.send(:resource).reset_password_token).to eq(token)
        end
      end

      # Resolving the tenant from the token means an unknown one reveals
      # nothing: it falls through to Devise's standard invalid-token handling
      # rather than the tenant-specific disabled page.
      it "GET /password/edit with an unknown token falls through to Devise, not the disabled page" do
        get "/auth/password/edit", params: { reset_password_token: "not-a-real-token" }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Password reset is currently disabled")
      end
    end

    context "when allow_password_reset is true" do
      before { set_reset(true) }

      it "POST /password sends a reset email" do
        expect {
          post "/auth/password", params: { user: { email: user.email } }
        }.to change { ActionMailer::Base.deliveries.size }.by(1)
      end
    end
  end

  # ==========================================================================
  # Audit ledger — password_reset_requested / password_reset_completed
  # ==========================================================================
  describe "audit events" do
    it "records password_reset_requested after sending the reset email" do
      expect {
        post user_password_path, params: { user: { email: "pwd@example.com" } }
      }.to change { Authentication::Event.where(event: "password_reset_requested", customer_id: customer.id).count }.by(1)
    end

    it "records password_reset_completed after a successful reset" do
      raw_token = user.send(:set_reset_password_token)

      expect {
        patch user_password_path, params: {
          user: {
            reset_password_token: raw_token,
            password: "newpassword123",
            password_confirmation: "newpassword123"
          }
        }
      }.to change { Authentication::Event.where(event: "password_reset_completed", user_id: user.id).count }.by(1)
    end
  end

  # ==========================================================================
  # B6 — password-reset request throttle (5 requests / 15 min per customer+IP)
  # ==========================================================================
  describe "POST /auth/password — throttle" do
    # Use a dedicated customer/user so this doesn't share the throttle
    # bucket (keyed on customer_id + remote_ip) with the requests made
    # elsewhere in this spec file against the outer let_it_be(:customer).
    let(:throttle_customer) { create(:customer) }
    let!(:throttle_user) { create(:user, customer: throttle_customer, email: "throttle@example.com", password: "password123") }

    before do
      ensure_customer_feature_module(throttle_customer, auth_module, status: :active)
      Authentication::Throttle.reset_store!
    end

    after { Authentication::Throttle.reset_store! }

    def request_reset
      post user_password_path, params: { user: { email: throttle_user.email } }
    end

    it "allows up to 5 reset requests within the window" do
      4.times { request_reset }
      request_reset
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects the 6th request to new_user_password_path with a throttled alert" do
      5.times { request_reset }
      request_reset
      expect(response).to redirect_to(new_user_password_path)
    end

    it "renders the throttled flash message" do
      5.times { request_reset }
      request_reset
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.password.throttled"))
    end

    it "does not send another reset email once throttled" do
      5.times { request_reset }
      ActionMailer::Base.deliveries.clear
      request_reset
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "records a throttled audit event once the limit is exceeded" do
      5.times { request_reset }
      expect { request_reset }
        .to change { Authentication::Event.where(event: "throttled", customer_id: throttle_customer.id).count }.by(1)
    end
  end

  # ==========================================================================
  # Per-email throttle — protects a fixed recipient even when the attacker
  # rotates source IPs (the per-IP bucket alone would never trip).
  # ==========================================================================
  describe "POST /auth/password — per-email throttle (IP rotation)" do
    let(:email_customer) { create(:customer) }
    let!(:email_user) { create(:user, customer: email_customer, email: "target@example.com", password: "password123") }

    before do
      ensure_customer_feature_module(email_customer, auth_module, status: :active)
      Authentication::Throttle.reset_store!
    end

    after { Authentication::Throttle.reset_store! }

    # Each request comes from a distinct IP so the per-IP bucket stays at 1 and
    # never trips — only the per-email bucket can throttle here.
    def request_reset_from(ip, email: "target@example.com")
      post user_password_path,
           params:  { user: { email: email } },
           headers: { "REMOTE_ADDR" => ip }
    end

    it "throttles a fixed recipient even as the source IP rotates" do
      5.times { |i| request_reset_from("203.0.113.#{i + 1}") }
      request_reset_from("203.0.113.99")
      expect(response).to redirect_to(new_user_password_path)
    end

    it "renders the throttled flash message on the email-bucket breach" do
      5.times { |i| request_reset_from("203.0.113.#{i + 1}") }
      request_reset_from("203.0.113.99")
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.password.throttled"))
    end

    it "records a throttled audit event when the email bucket trips across IPs" do
      5.times { |i| request_reset_from("198.51.100.#{i + 1}") }
      expect { request_reset_from("198.51.100.99") }
        .to change { Authentication::Event.where(event: "throttled", customer_id: email_customer.id).count }.by(1)
    end

    it "sends no further email once the recipient is throttled across IPs" do
      5.times { |i| request_reset_from("192.0.2.#{i + 1}") }
      ActionMailer::Base.deliveries.clear
      request_reset_from("192.0.2.99")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "does not leak existence — an unknown email is throttled identically" do
      5.times { |i| request_reset_from("203.0.113.#{i + 1}", email: "ghost@example.com") }
      request_reset_from("203.0.113.99", email: "ghost@example.com")
      # Byte-identical to the known-email path: same redirect either way.
      expect(response).to redirect_to(new_user_password_path)
    end

    it "keys the bucket per email — a different recipient is unaffected" do
      5.times { |i| request_reset_from("203.0.113.#{i + 1}", email: "target@example.com") }
      request_reset_from("203.0.113.99", email: "other@example.com")
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
