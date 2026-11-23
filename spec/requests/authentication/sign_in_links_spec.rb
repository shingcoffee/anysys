# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::SignInLinks", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:user) { create(:user, :admin, customer: customer, email: "admin@acme.test") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    # Authentication::Throttle is backed by a process-shared store, so without
    # this the per-IP sign-in-link bucket carries over between examples and the
    # sixth request in the process gets throttled instead of exercised.
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  describe "POST /auth/sign_in_link" do
    it "always redirects to check-email and sends a link for a confirmed user" do
      expect {
        perform_enqueued_jobs do
          post sign_in_links_path, params: { user: { email: user.email } }
        end
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to redirect_to(sign_in_link_check_email_path)
      follow_redirect!
      expect(response.body).to include("Check your inbox")
      expect(response.body).to include(user.email)
    end

    it "still shows check-email for an unknown address" do
      expect {
        perform_enqueued_jobs do
          post sign_in_links_path, params: { user: { email: "ghost@acme.test" } }
        end
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(response).to redirect_to(sign_in_link_check_email_path)
    end

    it "does not sign the visitor in" do
      post sign_in_links_path, params: { user: { email: user.email } }
      expect(controller.user_signed_in?).to be(false)
    end

    it "normalizes the address the same way the sign-in form entry point does" do
      post sign_in_links_path, params: { user: { email: "  ADMIN@Acme.TEST " } }

      follow_redirect!
      expect(response.body).to include("admin@acme.test")
      expect(user.reload.sign_in_token).to be_present
    end

    it "tolerates a POST with no user params" do
      post sign_in_links_path
      expect(response).to redirect_to(sign_in_link_check_email_path)
    end

    it "tolerates a POST with user as an array" do
      post sign_in_links_path, params: { user: ["not-a-hash"] }
      expect(response).to redirect_to(sign_in_link_check_email_path)
    end

    context "when platform captcha is configured" do
      it "accepts a check-email resend without a captcha token while under the URL throttle" do
        post sign_in_links_path, params: { user: { email: user.email } }
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)

        expect {
          perform_enqueued_jobs do
            post sign_in_links_path, params: { user: { email: user.email } }
          end
        }.to change { ActionMailer::Base.deliveries.size }
      end
    end
  end

  describe "GET /auth/sign_in_link" do
    def raw_token_for(record)
      raw, hashed = Devise.token_generator.generate(Authentication::User, :sign_in_token)
      record.update_columns(sign_in_token: hashed, sign_in_token_sent_at: Time.current)
      raw
    end

    it "signs the user in and sends them to the AI Assistant" do
      get sign_in_link_path, params: { token: raw_token_for(user) }

      expect(controller.user_signed_in?).to be(true)
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "tracks a passwordless sign-in link session exactly once" do
      user.update_columns(encrypted_password: "")
      token = raw_token_for(user)

      expect {
        get sign_in_link_path, params: { token: token }
      }.to change { user.reload.sign_in_count }.by(1)

      expect(controller.user_signed_in?).to be(true)
      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.current_sign_in_at).to be_present
    end

    it "sends a member to their member surface" do
      member = create(:user, :member, customer: customer, email: "member@acme.test")
      get sign_in_link_path, params: { token: raw_token_for(member) }

      expect(response).to redirect_to("/#{customer.id}/member")
    end

    # The emailed link is a replacement for the PASSWORD, not for the second
    # factor. Before this was fixed, clicking it handed out a session with
    # mfa_verified already true, so mailbox access alone defeated an enrolled
    # TOTP for every user except the platform owner.
    it "challenges an MFA-enforced user for their second factor" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      get sign_in_link_path, params: { token: raw_token_for(user) }

      expect(response).to redirect_to(mfa_session_path(customer.id))
      expect(session[:mfa_verified]).to be(false)
    end

    it "sends a user with an unfinished MFA setup to the setup page" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: false)
      get sign_in_link_path, params: { token: raw_token_for(user) }

      expect(response).to redirect_to(mfa_setup_path(customer.id))
      expect(session[:mfa_verified]).to be(false)
    end

    it "does not let an MFA-enforced user reach the dashboard on the link alone" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      get sign_in_link_path, params: { token: raw_token_for(user) }

      get admin_dashboard_path(customer.id)
      expect(response).to redirect_to(mfa_session_path(customer.id))
    end

    it "rejects an invalid token" do
      get sign_in_link_path, params: { token: "bogus" }
      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(response.body).to include("invalid or has expired")
    end

    it "audits a rejected token the way a failed password attempt is audited" do
      expect { get sign_in_link_path, params: { token: "bogus" } }
        .to change { Authentication::Event.where(event: "login_failed").count }.by(1)
    end

    it "rejects a replayed token" do
      token = raw_token_for(user)
      get sign_in_link_path, params: { token: token }
      delete destroy_user_session_path

      get sign_in_link_path, params: { token: token }
      expect(response).to redirect_to(new_user_session_path)
      expect(controller.user_signed_in?).to be(false)
    end

    # Mail clients, security proxies, and link scanners probe URLs before the
    # human ever clicks. A HEAD probe must not burn the one-time token.
    it "does not consume the token on a HEAD prefetch" do
      token = raw_token_for(user)

      head sign_in_link_path, params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(user.reload.sign_in_token).to be_present
      expect(controller.user_signed_in?).to be(false)

      get sign_in_link_path, params: { token: token }
      expect(controller.user_signed_in?).to be(true)
    end

    # The secret is in the query string, so it lands in the address bar,
    # browser history, and the Referer header of anything the rendered page
    # subsequently requests. `no-store` also keeps the back/forward cache from
    # handing the previous user's link to the next person on a shared device.
    it "keeps the token out of the Referer and out of caches" do
      get sign_in_link_path, params: { token: raw_token_for(user) }

      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "hardens the response even when the token is rejected" do
      get sign_in_link_path, params: { token: "not-a-real-token" }

      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "GET /auth/sign_in_link/check_email" do
    it "redirects to sign-in when there is no pending request" do
      get sign_in_link_check_email_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "does not embed a captcha widget on the resend form" do
      post sign_in_links_path, params: { user: { email: user.email } }
      Captcha::Providers::Aliyun
      create(:captcha_provider_settings, enabled: true)

      get sign_in_link_check_email_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("captcha_verify_param")
    end
  end

  describe "already signed in" do
    it "bounces an admin to the AI Assistant" do
      sign_in user
      get sign_in_link_check_email_path
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "bounces a member to their member surface" do
      member = create(:user, :member, customer: customer, email: "signed_in@acme.test")
      sign_in member
      get sign_in_link_check_email_path
      expect(response).to redirect_to("/#{customer.id}/member")
    end
  end
end
