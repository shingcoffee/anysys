# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Operation::Disable do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :with_mfa, customer: customer) }
  let(:totp)     { ROTP::TOTP.new(user.otp_secret) }

  it "disables MFA when code is valid" do
    result = described_class.call(user: user, code: totp.now)

    expect(result).to be_success
    user.reload
    expect(user.mfa_required?).to be(false)
    expect(user.otp_secret).to be_nil
  end

  it "fails when the code is wrong and leaves MFA on" do
    result = described_class.call(user: user, code: "000000")

    expect(result).not_to be_success
    expect(user.reload.mfa_required?).to be(true)
  end

  it "fails when MFA is not currently enabled" do
    user.disable_mfa!

    result = described_class.call(user: user, code: "000000")
    expect(result).not_to be_success
    expect(result.errors[:base]).to include(/not enabled/i)
  end

  it "rejects non-member users" do
    admin = create(:user, :admin, :with_mfa, customer: customer)
    totp_admin = ROTP::TOTP.new(admin.otp_secret)

    result = described_class.call(user: admin, code: totp_admin.now)
    expect(result).not_to be_success
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
      expect(user.reload.mfa_required?).to be(true)
    end

    it "clears the throttle on a successful disable" do
      3.times { described_class.call(user: user, code: "000000") }

      result = described_class.call(user: user, code: totp.now)
      expect(result).to be_success
      expect(user.reload.mfa_required?).to be(false)
    end
  end
end
