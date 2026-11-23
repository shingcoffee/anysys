# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public sign-in trusted device", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:user) { create(:user, :with_mfa, :admin, customer: customer, password: "password123") }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before { ensure_customer_feature_module(customer, auth_module, status: :active) }

  # Plants a signed trusted_device cookie into the session by driving the
  # real MFA verification flow (sign in, then POST the OTP with trust_device=1).
  # This mirrors the actual browser path and ensures the cookie is signed with
  # the same key the app reads during the subsequent sign-in request.
  def plant_trusted_device_cookie
    sign_in user
    totp_code = ROTP::TOTP.new(user.otp_secret).now
    post mfa_session_path(customer.id), params: { otp_code: totp_code, trust_device: "1" }
    sign_out user
    expect(response.cookies["trusted_device"]).to be_present
  end

  def sign_in_via_home_page
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end

  describe "POST /auth/sign_in with a valid trusted-device cookie" do
    before { plant_trusted_device_cookie }

    it "skips MFA and redirects to the AI Assistant (not the MFA verify page)" do
      sign_in_via_home_page
      expect(response).not_to redirect_to(mfa_session_path(customer.id))
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end
  end

  describe "POST /auth/sign_in without a trusted-device cookie" do
    it "redirects to the MFA verify page" do
      sign_in_via_home_page
      expect(response).to redirect_to(mfa_session_path(customer.id))
    end
  end
end
