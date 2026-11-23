# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::MfaSessionVerification do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :with_mfa, customer: customer) }
  let(:session) { {} }

  let(:host) do
    Class.new do
      include Authentication::MfaSessionVerification

      attr_accessor :session, :current_user

      def initialize(session:, current_user:)
        @session = session
        @current_user = current_user
      end

      public :mark_mfa_verified!, :clear_mfa_verification!, :mfa_session_verified?
    end.new(session: session, current_user: user)
  end

  describe "#mark_mfa_verified! / #mfa_session_verified?" do
    it "is true after the session is marked against the current secret" do
      host.mark_mfa_verified!

      expect(session[:mfa_verified]).to be(true)
      expect(session[:mfa_secret_digest]).to eq(
        Authentication::MfaSessionVerification.secret_digest(user)
      )
      expect(host.mfa_session_verified?).to be(true)
    end

    it "is false after the user's otp_secret is rotated, even though the flag remains" do
      host.mark_mfa_verified!
      expect(host.mfa_session_verified?).to be(true)

      user.update!(otp_secret: ROTP::Base32.random)

      expect(session[:mfa_verified]).to be(true)
      expect(host.mfa_session_verified?).to be(false)
    end

    it "is false when nothing was ever marked" do
      expect(host.mfa_session_verified?).to be(false)
    end
  end

  describe "#clear_mfa_verification!" do
    it "removes both the verified flag and the secret digest" do
      host.mark_mfa_verified!
      host.clear_mfa_verification!

      expect(session).not_to have_key(:mfa_verified)
      expect(session).not_to have_key(:mfa_secret_digest)
      expect(host.mfa_session_verified?).to be(false)
    end
  end

  describe ".secret_digest" do
    it "returns nil for a user with no OTP secret" do
      bare = create(:user, customer: customer)

      expect(described_class.secret_digest(bare)).to be_nil
    end

    it "returns nil when the user is missing" do
      expect(described_class.secret_digest(nil)).to be_nil
    end
  end
end
