# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::ResetToken do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :mfa_configured, customer: customer) }

  describe ".generate and .verify" do
    it "round-trips a token bound to a user and otp_secret" do
      token  = described_class.generate(user)
      result = described_class.verify(token)

      expect(result).to be_success
      expect(result.user).to eq(user)
    end

    it "fails verification when the otp_secret has changed" do
      token = described_class.generate(user)
      user.update!(otp_secret: ROTP::Base32.random)

      result = described_class.verify(token)
      expect(result).not_to be_success
      expect(result.reason).to eq(:fingerprint_mismatch)
    end

    it "fails verification after the TTL has passed" do
      token = described_class.generate(user)

      travel_to(20.minutes.from_now) do
        result = described_class.verify(token)
        expect(result).not_to be_success
        expect(result.reason).to eq(:expired_or_invalid)
      end
    end

    it "fails verification when the token is tampered" do
      token = described_class.generate(user)
      result = described_class.verify(token + "x")

      expect(result).not_to be_success
      expect(result.reason).to eq(:expired_or_invalid)
    end

    it "fails verification when the user is not a member" do
      admin = create(:user, :admin, :mfa_configured, customer: customer)
      token = described_class.generate(admin)

      result = described_class.verify(token)
      expect(result).not_to be_success
      expect(result.reason).to eq(:not_a_member)
    end

    it "rejects a token whose customer_id does not match the user's current customer" do
      # Defense-in-depth: token payload's customer_id must match the loaded
      # user's customer_id. This prevents cross-tenant replay even if user
      # ids ever collided across tenants.
      token = described_class.generate(user)

      # Tamper with the verifier payload by re-signing with a different
      # customer_id. The cleanest way is to mint a token whose payload
      # claims a different customer_id but the user's id, then check the
      # lookup misses (returns nil → :expired_or_invalid).
      forged_payload = {
        user_id:     user.id,
        customer_id: user.customer_id + 1,
        fingerprint: described_class.fingerprint(user.otp_secret)
      }
      forged_token = Rails.application.message_verifier(:member_mfa_reset)
                       .generate(forged_payload, purpose: :consume, expires_in: 15.minutes)

      result = described_class.verify(forged_token)
      expect(result).not_to be_success
      expect(result.reason).to eq(:expired_or_invalid)
    end
  end
end
