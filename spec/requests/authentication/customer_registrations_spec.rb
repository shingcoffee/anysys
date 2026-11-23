# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::CustomerRegistrations", type: :request do
  def sign_up(email: "founder@acme.test")
    post customer_registration_path, params: { user: { email: email } }
  end

  before { Authentication::Throttle.reset_store! }
  after  { Authentication::Throttle.reset_store! }

  describe "GET /auth/sign_up" do
    it "renders a minimal email-only form" do
      get new_customer_registration_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create an account")
      expect(response.body).to include('name="user[email]"')
      expect(response.body).not_to include('name="user[password]"')
      expect(response.body).not_to include('name="user[first_name]"')
      expect(response.body).not_to include("/auth/customers/")
    end

    it "renders the disabled page when the platform kill switch is off" do
      Authentication::PlatformSettings.instance.update!(allow_customer_signup: false)
      get new_customer_registration_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Account sign-up is currently disabled")
    end

    it "sends a signed-in admin back to the AI Assistant" do
      customer = create(:customer)
      admin = create(:user, :admin, customer: customer, password: "password123")
      sign_in admin
      get new_customer_registration_path
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end
  end

  describe "POST /auth/sign_up" do
    it "does not create a tenant and redirects to check-email while enqueueing mail" do
      before_customers = Customer.count
      before_users = Authentication::User.count

      expect {
        sign_up
      }.to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)

      expect(Customer.count).to eq(before_customers)
      expect(Authentication::User.count).to eq(before_users)
      expect(response).to redirect_to(customer_registration_check_email_path)
      follow_redirect!
      expect(response.body).to include("Please confirm your email.")
      expect(response.body).to include("founder@acme.test")
      expect(response.body).to include("Check your inbox")
    end

    it "does not sign the user in" do
      sign_up
      expect(controller.user_signed_in?).to be(false)
    end

    it "treats a taken email the same as an unknown one" do
      create(:user, email: "dup@acme.test")

      expect {
        sign_up(email: "dup@acme.test")
      }.not_to change(Customer, :count)

      expect(response).to redirect_to(customer_registration_check_email_path)
    end

    it "does not enqueue mail for a taken email" do
      create(:user, email: "taken-mail@acme.test")

      expect {
        sign_up(email: "taken-mail@acme.test")
      }.not_to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)
    end

    it "re-renders the form for an invalid email format without creating records" do
      expect {
        sign_up(email: "not-an-email")
      }.not_to change(Customer, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not 500 when user is posted as an array" do
      expect {
        post customer_registration_path, params: { user: ["not-a-hash"] }
      }.not_to change(Customer, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not enqueue mail when the kill switch is off" do
      Authentication::PlatformSettings.instance.update!(allow_customer_signup: false)
      before_customers = Customer.count
      before_users = Authentication::User.count

      expect {
        sign_up
      }.not_to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)

      expect(Customer.count).to eq(before_customers)
      expect(Authentication::User.count).to eq(before_users)
      expect(response.body).to include("Account sign-up is currently disabled")
    end

    it "throttles the 6th POST in the window" do
      5.times { |i| sign_up(email: "flood#{i}@acme.test") }
      sign_up(email: "flood5@acme.test")

      expect(response).to redirect_to(new_customer_registration_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.customer_signup.throttled"))
    end

    context "when platform captcha is configured" do
      before do
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)
      end

      it "accepts a POST without a captcha token while under the URL throttle" do
        expect {
          sign_up(email: "bot@acme.test")
        }.to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)
      end
    end
  end

  describe "POST /auth/sign_up/resend" do
    it "re-enqueues mail from the session email" do
      sign_up(email: "resend-me@acme.test")

      expect {
        post customer_registration_resend_path
      }.to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)

      expect(response).to redirect_to(customer_registration_check_email_path)
    end

    it "redirects to sign-up when the session has no email" do
      post customer_registration_resend_path
      expect(response).to redirect_to(new_customer_registration_path)
    end

    it "throttles the 6th request in the window (create + resends share the IP bucket)" do
      sign_up(email: "resend-flood@acme.test")
      4.times { post customer_registration_resend_path }
      post customer_registration_resend_path

      expect(response).to redirect_to(new_customer_registration_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.customer_signup.throttled"))
    end

    context "when platform captcha is configured" do
      before do
        sign_up(email: "resend-bot@acme.test")
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)
      end

      it "accepts a resend without a captcha token while under the URL throttle" do
        expect {
          post customer_registration_resend_path
        }.to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)
      end
    end
  end

  describe "GET /auth/sign_up/check_email" do
    it "redirects to sign-up when there is no pending confirmation" do
      get customer_registration_check_email_path
      expect(response).to redirect_to(new_customer_registration_path)
    end

    it "does not embed a captcha widget on the resend form" do
      sign_up(email: "widget-resend@acme.test")
      Captcha::Providers::Aliyun
      create(:captcha_provider_settings, enabled: true)

      get customer_registration_check_email_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("captcha_verify_param")
    end
  end

  describe "GET /auth/sign_up/confirm" do
    it "creates a confirmed admin, signs them in, and redirects to the AI Assistant" do
      token = Authentication::CustomerSignupToken.generate("confirm-me@acme.test")

      expect {
        get customer_registration_confirm_path, params: { token: token }
      }.to change(Customer, :count).by(1)
        .and change(Authentication::User, :count).by(1)

      user = Authentication::User.find_by!(email: "confirm-me@acme.test")
      expect(user).to be_confirmed
      expect(user.admin?).to be(true)
      expect(controller.user_signed_in?).to be(true)
      expect(response).to redirect_to(admin_assistant_path(user.customer_id))
    end

    it "does not create a second customer on a repeated confirm" do
      token = Authentication::CustomerSignupToken.generate("once@acme.test")
      get customer_registration_confirm_path, params: { token: token }

      expect {
        get customer_registration_confirm_path, params: { token: token }
      }.not_to change(Customer, :count)
    end

    # The token is a stateless encrypted message with a 3-day TTL and spending
    # it records nothing, so signing in an already-confirmed address would make
    # the welcome email a password-equivalent bearer credential for 72 hours
    # with no way to revoke it. Registration is already complete for these
    # users, so they go through the normal sign-in gate (which re-applies MFA).
    it "does not create a second tenant, or a session, when the email already belongs to a member" do
      other = create(:customer)
      member = create(:user, :member, customer: other, email: "member@other.test")
      token = Authentication::CustomerSignupToken.generate(member.email)

      expect {
        get customer_registration_confirm_path, params: { token: token }
      }.not_to change(Customer, :count)

      expect(controller.user_signed_in?).to be(false)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "is single-use: replaying a spent token does not re-establish a session" do
      token = Authentication::CustomerSignupToken.generate("replay@acme.test")
      get customer_registration_confirm_path, params: { token: token }
      expect(controller.user_signed_in?).to be(true)

      reset!

      get customer_registration_confirm_path, params: { token: token }
      expect(controller.user_signed_in?).to be(false)
      expect(response).to redirect_to(new_user_session_path)
    end

    # Two concurrent confirms of the same link — a double-clicked email button,
    # or a mail client prefetching while the human clicks. The loser's insert
    # trips the unique index on LOWER(email), so registration succeeded but not
    # in this request. Showing it the signup form for an address that now
    # exists would be a dead end.
    it "sends the loser of a concurrent confirm to sign-in" do
      email = "race@acme.test"
      token = Authentication::CustomerSignupToken.generate(email)

      # Stand in for the winning request committing between our lookup and our
      # insert: the account exists by the time CustomerSignup reports failure.
      allow(Authentication::CustomerSignup).to receive(:call) do
        create(:user, :admin, email: email)
        Authentication::CustomerSignup::Result.new(
          success?: false, user: nil, customer: nil,
          errors: [ I18n.t("auth.customer_registrations.errors.retry") ]
        )
      end

      get customer_registration_confirm_path, params: { token: token }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to eq(I18n.t("auth.flash.customer_signup.already_confirmed"))
    end

    it "still shows the signup form when registration failed for an unrelated reason" do
      token = Authentication::CustomerSignupToken.generate("broken@acme.test")

      allow(Authentication::CustomerSignup).to receive(:call).and_return(
        Authentication::CustomerSignup::Result.new(
          success?: false, user: nil, customer: nil, errors: [ "Something went wrong" ]
        )
      )

      get customer_registration_confirm_path, params: { token: token }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "keeps the token out of the Referer and out of caches" do
      token = Authentication::CustomerSignupToken.generate("headers@acme.test")
      get customer_registration_confirm_path, params: { token: token }

      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "confirms an existing unconfirmed user without creating a customer" do
      existing = create(:user, :admin, :unconfirmed, email: "pending@acme.test")
      token = Authentication::CustomerSignupToken.generate(existing.email)

      expect {
        get customer_registration_confirm_path, params: { token: token }
      }.not_to change(Customer, :count)

      expect(existing.reload).to be_confirmed
      expect(controller.user_signed_in?).to be(true)
    end

    it "renders expired for a garbage token" do
      get customer_registration_confirm_path, params: { token: "not-a-real-token" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Link expired")
    end

    it "renders expired after the token TTL and does not create a customer" do
      token = Authentication::CustomerSignupToken.generate("late@acme.test")

      travel(Authentication::CustomerSignupToken::TTL + 1.second) do
        expect {
          get customer_registration_confirm_path, params: { token: token }
        }.not_to change(Customer, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Link expired")
      end
    end

    it "does not provision on HEAD" do
      token = Authentication::CustomerSignupToken.generate("head-scan@acme.test")

      expect {
        head customer_registration_confirm_path, params: { token: token }
      }.not_to change(Customer, :count)

      expect(response).to have_http_status(:ok)
    end

    it "renders the disabled page when the kill switch is off" do
      Authentication::PlatformSettings.instance.update!(allow_customer_signup: false)
      token = Authentication::CustomerSignupToken.generate("killed@acme.test")

      expect {
        get customer_registration_confirm_path, params: { token: token }
      }.not_to change(Customer, :count)

      expect(response.body).to include("Account sign-up is currently disabled")
    end
  end
end
