# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::User, "atomic TOTP replay protection" do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :with_mfa, customer: customer) }

  # 5s into a period so ±15s drift stays inside the current 30s step.
  let(:period_start) { Time.utc(2026, 6, 1, 12, 0, 0) }
  let(:inside_period) { period_start + 5.seconds }

  def totp
    ROTP::TOTP.new(user.otp_secret)
  end

  def code_at(time)
    totp.at(time)
  end

  it "accepts a valid code once, then rejects an immediate replay of the same code" do
    travel_to(inside_period) do
      code = code_at(inside_period)

      expect(user.verify_otp(code)).to be(true)
      expect(user.verify_otp(code)).to be(false)
    end
  end

  it "advances last_otp_at to the consumed timecode" do
    travel_to(inside_period) do
      expect(user.last_otp_at).to be_nil
      expect(user.verify_otp(code_at(inside_period))).to be(true)
    end

    expect(user.last_otp_at).to eq(period_start)
    expect(user.reload.last_otp_at).to eq(period_start)
  end

  it "rejects a code from an earlier timecode than the one already consumed" do
    travel_to(inside_period) do
      expect(user.verify_otp(code_at(inside_period))).to be(true)
    end

    # Travel back so the earlier step is "current" for ROTP; `after: last_otp_at`
    # and the conditional last_otp_at UPDATE must still refuse it.
    travel_to(period_start - 25.seconds) do
      expect(user.verify_otp(code_at(period_start - 30.seconds))).to be(false)
    end
    expect(user.reload.last_otp_at).to eq(period_start)
  end

  it "accepts a fresh code from a later timecode" do
    travel_to(inside_period) do
      expect(user.verify_otp(code_at(inside_period))).to be(true)
    end

    later = period_start + 30.seconds
    travel_to(later + 5.seconds) do
      expect(user.verify_otp(code_at(later))).to be(true)
    end
    expect(user.reload.last_otp_at).to eq(later)
  end

  it "rejects an old secret on an instance loaded before rotation" do
    stale = Authentication::User.find(user.id)
    code = ROTP::TOTP.new(stale.otp_secret).at(inside_period)
    user.generate_otp_secret!

    travel_to(inside_period) { expect(stale.verify_otp(code)).to be(false) }
    expect(user.reload.last_otp_at).to be_nil
  end

  it "rechecks the replay clock when a second verifier has a stale last_otp_at" do
    stale = Authentication::User.find(user.id)
    travel_to(inside_period) do
      code = code_at(inside_period)
      expect(user.verify_otp(code)).to be(true)
      expect(stale.verify_otp(code)).to be(false)
    end
    expect(user.reload.last_otp_at).to eq(period_start)
  end

  it "resets the replay clock for a different secret, allowing its first code in the same time period" do
    travel_to(inside_period) do
      expect(user.verify_otp(code_at(inside_period))).to be(true)
      user.generate_otp_secret!
      expect(user.last_otp_at).to be_nil
      expect(user.verify_otp(ROTP::TOTP.new(user.otp_secret).at(inside_period))).to be(true)
    end
  end
end
