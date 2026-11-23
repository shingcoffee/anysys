require "rails_helper"

RSpec.describe "Authentication::Confirmations", type: :request do
  # Devise mail is enqueued; deliver it so examples can read the mailbox.
  around { |example| perform_enqueued_jobs { example.run } }

  let_it_be(:customer) { create(:customer) }
  # Explicitly a member — that is what RegistrationsController assigns on
  # self-serve sign-up, so it is the role an unconfirmed user really carries.
  # It matters twice: the landing assertions below resolve to the member
  # surface, and confirmation resend stays gated by the tenant sign-up toggle
  # (an unconfirmed *admin* is exempt from that gate by design).
  let!(:user) do
    create(:user, :unconfirmed, :member,
           customer: customer,
           email: "newuser@example.com")
  end
  let(:valid_token) do
    # Generate a valid Devise confirmation token using the token_generator
    raw_token, hashed = Devise.token_generator.generate(Authentication::User, :confirmation_token)
    user.update_columns(confirmation_token: hashed, confirmation_sent_at: 1.minute.ago)
    raw_token
  end

  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  def set_signup(enabled)
    fm = FeatureModules::Module.find_by!(key: "authentication")
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    cfm.update!(status: :active,
                configuration: { "allow_registration" => enabled }.to_json)
  end

  describe "GET /:cid/auth/confirmation" do
    context "when sign-up is enabled" do
      before { set_signup(true) }

      it "confirms the user with a valid token and signs them in" do
        get "/auth/confirmation", params: { confirmation_token: valid_token }
        expect(user.reload.confirmed_at).to be_present
        expect(controller.user_signed_in?).to be(true)
        expect(response).to redirect_to(member_dashboard_path(customer.id))
      end

      it "does not consume the confirmation token on HEAD" do
        head "/auth/confirmation", params: { confirmation_token: valid_token }

        expect(response).to have_http_status(:ok)
        expect(user.reload.confirmed_at).to be_nil
        expect(user.confirmation_token).to be_present
      end

      # The confirmed notice is set before finish_sign_in, whose reset_session
      # used to wipe it (the flash lives in the session), so the user landed on
      # the dashboard with no feedback at all.
      it "keeps the confirmed notice across the session rotation" do
        get "/auth/confirmation", params: { confirmation_token: valid_token }

        expect(flash[:notice]).to eq(I18n.t("devise.confirmations.confirmed"))

        # And it is still there for the page the redirect lands on, i.e. it was
        # written into the post-rotation session rather than merely surviving
        # in memory for the current request.
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("devise.confirmations.confirmed"))
      end

      # Same reasoning as the sign-in link: the secret is in the query string,
      # so it reaches the address bar, browser history, and the Referer of
      # anything the rendered page goes on to request.
      it "keeps the token out of the Referer and out of caches" do
        get "/auth/confirmation", params: { confirmation_token: valid_token }

        expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      # Consuming someone else's confirmation link would otherwise silently
      # swap an authenticated session to that account, so an attacker who mails
      # their own link could get a victim working inside the attacker's tenant.
      # Reconfirmable is off, so confirmation only ever happens at sign-up and
      # nobody legitimately needs it while signed in.
      it "does not swap an already-authenticated session to the token's account" do
        signed_in_user = create(:user, :admin, customer: customer)
        sign_in signed_in_user

        get "/auth/confirmation", params: { confirmation_token: valid_token }

        expect(response).to redirect_to(admin_assistant_path(customer.id))
        expect(user.reload.confirmed_at).to be_nil
        expect(controller.current_user).to eq(signed_in_user)
      end
    end

    context "when sign-up is disabled" do
      before { set_signup(false) }

      it "still confirms the user with a valid token and signs them in" do
        get "/auth/confirmation", params: { confirmation_token: valid_token }
        expect(user.reload.confirmed_at).to be_present
        expect(controller.user_signed_in?).to be(true)
        expect(response).to redirect_to(member_dashboard_path(customer.id))
      end
    end
  end

  describe "POST /:cid/auth/confirmation" do
    context "when sign-up is enabled" do
      before { set_signup(true) }

      it "resends the confirmation email scoped to the tenant" do
        expect {
          post "/auth/confirmation",
               params: { user: { email: "newuser@example.com" } }
        }.to change { ActionMailer::Base.deliveries.size }.by(1)
      end
    end

    context "when sign-up is disabled" do
      before { set_signup(false) }

      it "does not send email and still redirects (paranoid, no leak)" do
        expect {
          post "/auth/confirmation",
               params: { user: { email: "newuser@example.com" } }
        }.not_to change { ActionMailer::Base.deliveries.size }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    # resource_params used to `require(:user)` and raise ParameterMissing while
    # the throttle before_action read the same value with a safe `dig`. A 400 on
    # this endpoint is a distinguishable response on a surface that is
    # otherwise deliberately uniform.
    context "with malformed params" do
      before { set_signup(true) }

      it "treats a POST with no user key as an unknown address" do
        expect {
          post "/auth/confirmation"
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to redirect_to(new_user_session_path)
      end

      it "treats a POST with a blank email as an unknown address" do
        expect {
          post "/auth/confirmation", params: { user: { email: "" } }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to redirect_to(new_user_session_path)
      end

      it "treats a POST with user as an array as an unknown address" do
        expect {
          post "/auth/confirmation", params: { user: ["not-a-hash"] }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  # The confirmation click is a passwordless FIRST factor. It must not stand in
  # for an enrolled second factor: before this was fixed, confirming with TOTP
  # already enrolled produced a fully MFA-satisfied session.
  describe "MFA interaction" do
    before { set_signup(true) }

    it "signs a user with no otp_secret straight in" do
      get "/auth/confirmation", params: { confirmation_token: valid_token }
      expect(response).to redirect_to(member_dashboard_path(customer.id))
      expect(session[:mfa_verified]).to be(true)
    end

    it "challenges a user who already has TOTP enforced" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      get "/auth/confirmation", params: { confirmation_token: valid_token }

      expect(response).to redirect_to(mfa_session_path(customer.id))
      expect(session[:mfa_verified]).to be(false)
    end
  end

  describe "invalid or already-used tokens" do
    before { set_signup(true) }

    it "redirects a bogus token to sign in instead of 500ing on Devise's stock template" do
      get "/auth/confirmation", params: { confirmation_token: "bogus" }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq(I18n.t("auth.flash.confirmation.invalid"))
    end

    it "redirects GET /auth/confirmation/new to sign in" do
      get "/auth/confirmation/new"

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
