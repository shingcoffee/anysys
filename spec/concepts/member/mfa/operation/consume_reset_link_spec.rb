# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Operation::ConsumeResetLink do
  let_it_be(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, :with_mfa, customer: customer) }

  it "disables MFA on a valid token" do
    token  = Member::Mfa::ResetToken.generate(member)
    result = described_class.call(token: token)

    expect(result).to be_success
    expect(result.user).to eq(member)

    member.reload
    expect(member.otp_required_for_login).to be(false)
    expect(member.otp_secret).to be_nil
  end

  it "fails on an expired token" do
    token = Member::Mfa::ResetToken.generate(member)

    travel_to(20.minutes.from_now) do
      result = described_class.call(token: token)
      expect(result).not_to be_success
      expect(member.reload.mfa_required?).to be(true)
    end
  end

  it "fails on a tampered token" do
    token = Member::Mfa::ResetToken.generate(member)

    result = described_class.call(token: token + "x")
    expect(result).not_to be_success
    expect(member.reload.mfa_required?).to be(true)
  end

  it "fails when fingerprint no longer matches (consume after secret rotation)" do
    token = Member::Mfa::ResetToken.generate(member)
    member.update!(otp_secret: ROTP::Base32.random)

    result = described_class.call(token: token)
    expect(result).not_to be_success
  end

  it "rejects an admin-targeted token without modifying the admin's MFA" do
    admin = create(:user, :admin, :with_mfa, customer: customer)
    token = Member::Mfa::ResetToken.generate(admin)

    result = described_class.call(token: token)
    expect(result).not_to be_success
    expect(admin.reload.mfa_required?).to be(true)
  end

  it "is single-use even when the second consumer was preloaded before the first consume" do
    token = Member::Mfa::ResetToken.generate(member)
    stale = Authentication::User.find(member.id)
    allow(Member::Mfa::ResetToken).to receive(:lookup).and_return(stale)

    expect(described_class.call(token: token)).to be_success
    result = described_class.call(token: token)
    expect(result).not_to be_success
    expect(result.reason).to eq(:fingerprint_mismatch)
  end

  it "does not clear a replacement secret when lookup races rotation" do
    token = Member::Mfa::ResetToken.generate(member)
    stale = Authentication::User.find(member.id)
    member.generate_otp_secret!
    replacement = member.otp_secret
    allow(Member::Mfa::ResetToken).to receive(:lookup).and_return(stale)

    result = described_class.call(token: token)

    expect(result).not_to be_success
    expect(result.reason).to eq(:fingerprint_mismatch)
    expect(member.reload.otp_secret).to eq(replacement)
    expect(member).to be_mfa_required
  end

  it "rechecks the member role after a preloaded account is promoted" do
    token = Member::Mfa::ResetToken.generate(member)
    stale = Authentication::User.find(member.id)
    expect(stale.member?).to be(true)
    role = customer.roles.system.find_by!(key: "admin")
    expect(UserRoles::Operation::Assign.call(user: member, role_ids: [role.id])).to be_success
    allow(Member::Mfa::ResetToken).to receive(:lookup).and_return(stale)

    result = described_class.call(token: token)

    expect(result).not_to be_success
    expect(result.reason).to eq(:not_a_member)
    expect(member.reload).to be_mfa_required
  end

  it "rejects a stale direct disable rather than clearing a newer factor" do
    stale = Authentication::User.find(member.id)
    member.generate_otp_secret!
    replacement = member.otp_secret

    expect { stale.disable_mfa! }.to raise_error(ActiveRecord::StaleObjectError)
    expect(member.reload.otp_secret).to eq(replacement)
    expect(member).to be_mfa_required
  end

  it "keeps the token and MFA usable when a surrounding recovery transaction rolls back" do
    token = Member::Mfa::ResetToken.generate(member)
    Authentication::User.transaction(requires_new: true) do
      expect(described_class.call(token: token)).to be_success
      raise ActiveRecord::Rollback
    end

    expect(member.reload).to be_mfa_required
    expect(described_class.call(token: token)).to be_success
  end

  it "rejects a token that expires while waiting to acquire the account lock" do
    token = Member::Mfa::ResetToken.generate(member)
    allow_any_instance_of(Authentication::User).to receive(:with_lock).and_wrap_original do |method, *args, &block|
      travel_to(20.minutes.from_now) { method.call(*args, &block) }
    end

    result = described_class.call(token: token)

    expect(result).not_to be_success
    expect(result.reason).to eq(:expired_or_invalid)
    expect(member.reload).to be_mfa_required
  end
end
