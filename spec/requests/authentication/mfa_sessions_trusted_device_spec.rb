# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MFA session trusted device", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:user) { create(:user, :with_mfa, customer: customer, password: "password123") }

  # sign_in is the Devise request-spec helper. It places the user in a
  # signed-in-but-not-yet-MFA-verified state, matching what SessionsController
  # produces immediately after sign_in + reset_session.
  before { sign_in user }

  def valid_code
    ROTP::TOTP.new(user.otp_secret).now
  end

  describe "POST /:customer_id/auth/mfa/authenticate with trust_device=1" do
    it "creates a trusted device row when the box is checked" do
      expect {
        post mfa_session_path(customer.id), params: { otp_code: valid_code, trust_device: "1" }
      }.to change { user.trusted_devices.count }.by(1)
    end

    it "sets the signed trusted_device cookie when the box is checked" do
      post mfa_session_path(customer.id), params: { otp_code: valid_code, trust_device: "1" }
      expect(response.cookies["trusted_device"]).to be_present
    end

    it "stores the cookie with httponly and same_site: lax attributes" do
      post mfa_session_path(customer.id), params: { otp_code: valid_code, trust_device: "1" }
      # Set-Cookie may be a single String or an Array of strings depending on
      # how many cookies are being set. Normalise to a flat string for matching.
      set_cookie_header = Array(response.headers["Set-Cookie"]).join("\n")
      trusted_device_cookie = set_cookie_header.lines.select { |l| l.include?("trusted_device") }.join
      expect(trusted_device_cookie).not_to be_empty
      expect(trusted_device_cookie).to include("httponly")
      # Rails renders same_site: :lax as "samesite=lax" (lowercase) in test
      expect(trusted_device_cookie).to match(/samesite=lax/i)
    end

    it "does NOT create a row when the box is unchecked" do
      expect {
        post mfa_session_path(customer.id), params: { otp_code: valid_code }
      }.not_to change { user.trusted_devices.count }
    end

    it "does NOT set a cookie when the box is unchecked" do
      post mfa_session_path(customer.id), params: { otp_code: valid_code }
      expect(response.cookies["trusted_device"]).to be_blank
    end
  end

  describe "POST /:customer_id/auth/mfa/authenticate with invalid OTP" do
    it "does NOT create a row when the code is invalid" do
      expect {
        post mfa_session_path(customer.id), params: { otp_code: "000000", trust_device: "1" }
      }.not_to change { user.trusted_devices.count }
    end

    it "does NOT set a cookie when the code is invalid" do
      post mfa_session_path(customer.id), params: { otp_code: "000000", trust_device: "1" }
      expect(response.cookies["trusted_device"]).to be_blank
    end
  end
end
