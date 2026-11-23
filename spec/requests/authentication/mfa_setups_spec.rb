# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::MfaSetups", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  # Explicitly an admin: this tenant has mfa_enabled, which binds admins and
  # owners (members are opt-in), and the landing assertions expect the admin
  # surface. A role-less fixture would resolve to the member surface.
  let(:user) { create(:user, :admin, customer: customer, password: "password123") }

  before do
    ensure_customer_feature_module(customer, auth_module,
                                   configuration: { "mfa_enabled" => true }.to_json)
  end

  describe "GET /:customer_id/auth/mfa/setup" do
    context "when anonymous" do
      it "redirects to the sign-in page" do
        get mfa_setup_path(customer.id)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in" do
      before { sign_in user }

      it "generates an OTP secret for the user" do
        expect(user.otp_secret).to be_nil
        get mfa_setup_path(customer.id)
        expect(user.reload.otp_secret).to be_present
      end

      it "does not plant an OTP secret when the browser prefetches the page" do
        get mfa_setup_path(customer.id), headers: { "X-Sec-Purpose" => "prefetch" }

        expect(response).to have_http_status(:no_content)
        expect(user.reload.otp_secret).to be_nil
      end

      it "renders the setup instructions and manual-entry secret from the ERB" do
        get mfa_setup_path(customer.id)

        expect(response.body).to include("Set up 2FA")
        expect(response.body).to include("Scan the QR code with your authenticator app")
        expect(response.body).to include("Can't scan? Enter this key manually:")
        expect(response.body).to include("Verification code")
        expect(response.body).to include(user.reload.otp_secret)
        expect(response.body).to include("placeholder=\"000000\"")
        expect(response.body).to include('data-turbo="false"')
      end

      it "renders the QR code SVG" do
        get mfa_setup_path(customer.id)
        expect(response.body).to include("<svg")
      end

      it "sets no-store cache headers so the secret is never cached" do
        get mfa_setup_path(customer.id)
        # Rack's response-commit pipeline normalizes/dedupes Cache-Control
        # directives, so assert on the directives that matter rather than
        # the exact string the controller assigns.
        expect(response.headers["Cache-Control"]).to include("no-store")
        expect(response.headers["Cache-Control"]).to include("private")
        expect(response.headers["Pragma"]).to eq("no-cache")
      end

      it "does not regenerate the OTP secret when already MFA-configured" do
        get mfa_setup_path(customer.id)
        existing_secret = user.reload.otp_secret

        get mfa_setup_path(customer.id)
        expect(user.reload.otp_secret).to eq(existing_secret)
      end
    end
  end

  describe "POST /:customer_id/auth/mfa/setup" do
    before do
      sign_in user
      user.generate_otp_secret!
    end

    it "re-renders :show with 422 and a flash alert on an invalid code" do
      post mfa_setup_path(customer.id), params: { otp_code: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid verification code. Please try again.")
      expect(response.body).to include("Set up 2FA")
      expect(user.reload.otp_required_for_login).to be false
    end

    it "enables MFA and redirects an admin to the AI Assistant on a valid code" do
      totp = ROTP::TOTP.new(user.otp_secret)
      expect { post mfa_setup_path(customer.id), params: { otp_code: totp.now } }
        .to change { Authentication::Event.where(event: "mfa_enabled", user_id: user.id).count }.by(1)

      expect(user.reload.otp_required_for_login).to be true
      expect(response).to redirect_to(admin_assistant_path(customer.id))
      event = Authentication::Event.where(event: "mfa_enabled", user_id: user.id).last
      expect(event.metadata).to include("actor_id" => user.id, "source" => "self_service", "outcome" => "success")
    end

    it "shows the throttled flash instead of invalid-code after too many attempts" do
      throttle = instance_double(Authentication::Throttle, exceeded?: true)
      allow(Authentication::Throttle).to receive(:new).and_return(throttle)

      post mfa_setup_path(customer.id), params: { otp_code: ROTP::TOTP.new(user.otp_secret).now }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(I18n.t("auth.flash.mfa.throttled"))
      expect(user.reload.otp_required_for_login).to be false
    end
  end

  describe "POST /:customer_id/auth/mfa/setup — member routing" do
    let(:member_user) { create(:user, :member, customer: customer, password: "password123") }

    before do
      sign_in member_user
      member_user.generate_otp_secret!
    end

    it "redirects a member to the member dashboard after enabling MFA" do
      totp = ROTP::TOTP.new(member_user.otp_secret)
      post mfa_setup_path(customer.id), params: { otp_code: totp.now }

      expect(member_user.reload.otp_required_for_login).to be true
      expect(response).to redirect_to(member_dashboard_path(customer.id))
    end
  end

  describe "when MFA is already enforced" do
    let(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }

    before do
      sign_in user
      post mfa_session_path(customer.id), params: { otp_code: ROTP::TOTP.new(user.otp_secret).now }
    end

    it "does not re-render the TOTP secret on GET" do
      secret = user.otp_secret
      get mfa_setup_path(customer.id)

      expect(response).to redirect_to(admin_assistant_path(customer.id))
      follow_redirect!
      expect(response.body).not_to include(secret)
    end

    it "does not re-render the TOTP secret on POST" do
      secret = user.otp_secret
      post mfa_setup_path(customer.id), params: { otp_code: "000000" }

      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.reload.otp_secret).to eq(secret)
    end
  end
end
