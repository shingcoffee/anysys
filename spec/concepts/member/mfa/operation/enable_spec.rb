# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Operation::Enable do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :mfa_configured, customer: customer) }
  let(:totp)     { ROTP::TOTP.new(user.otp_secret) }

  it "enables MFA when code is valid and user is a member" do
    result = described_class.call(user: user, code: totp.now)

    expect(result).to be_success
    expect(user.reload.mfa_required?).to be(true)
  end

  it "fails when the code is wrong" do
    result = described_class.call(user: user, code: "000000")

    expect(result).not_to be_success
    expect(user.reload.mfa_required?).to be(false)
  end

  it "rejects non-member users" do
    admin = create(:user, :admin, :mfa_configured, customer: customer)
    totp_admin = ROTP::TOTP.new(admin.otp_secret)

    result = described_class.call(user: admin, code: totp_admin.now)

    expect(result).not_to be_success
    expect(result.errors[:base]).to include(/member/i)
  end

  it "generates an otp_secret if missing before verifying" do
    user_no_secret = create(:user, :member, customer: customer)
    user_no_secret.update_column(:otp_secret, nil)

    result = described_class.call(user: user_no_secret, code: "000000")
    expect(result).not_to be_success
    expect(user_no_secret.reload.otp_secret).to be_present
  end

  it "fails gracefully when user is nil" do
    result = described_class.call(user: nil, code: "123456")
    expect(result).not_to be_success
    expect(result.errors[:base]).to include(/member/i)
  end

  describe "OTP-attempt throttling" do
    before { Authentication::Throttle.reset_store! }

    after { Authentication::Throttle.reset_store! }

    it "throttles after 5 failed attempts and fails closed for a valid code" do
      5.times { described_class.call(user: user, code: "000000") }

      result = described_class.call(user: user, code: totp.now)
      expect(result).not_to be_success
      expect(result.errors[:base]).to include(described_class::THROTTLED)
      expect(user.reload.mfa_required?).to be(false)
    end

    it "clears the throttle on a successful enable" do
      3.times { described_class.call(user: user, code: "000000") }

      result = described_class.call(user: user, code: totp.now)
      expect(result).to be_success
      expect(user.reload.mfa_required?).to be(true)
    end
  end
end
