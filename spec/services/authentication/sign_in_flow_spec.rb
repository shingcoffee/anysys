# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::SignInFlow do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:user) { create(:user, customer: customer, email: "alice@example.com", password: "password123") }

  before { ensure_customer_feature_module(customer, auth_module, status: :active) }

  def call(email:, password:)
    described_class.call(email: email, password: password)
  end

  it "returns :invalid_credentials for an unknown email" do
    result = call(email: "nobody@example.com", password: "password123")
    expect(result.success?).to be(false)
    expect(result.next_action).to eq(:invalid_credentials)
  end

  it "returns :invalid_credentials on wrong password" do
    result = call(email: "alice@example.com", password: "wrong")
    expect(result.success?).to be(false)
    expect(result.next_action).to eq(:invalid_credentials)
  end

  it "returns :invalid_credentials when the user has no password set" do
    user.update_columns(encrypted_password: "")
    result = call(email: "alice@example.com", password: "")
    expect(result.success?).to be(false)
    expect(result.next_action).to eq(:invalid_credentials)
  end

  it "returns :invalid_credentials when authentication is disabled for the user's tenant" do
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).delete_all
    result = call(email: "alice@example.com", password: "password123")
    expect(result.success?).to be(false)
    expect(result.next_action).to eq(:invalid_credentials)
  end

  it "returns :authenticated for a valid user without MFA" do
    result = call(email: "alice@example.com", password: "password123")
    expect(result.success?).to be(true)
    expect(result.user).to eq(user)
    expect(result.next_action).to eq(:authenticated)
  end

  it "returns :mfa_setup_required when tenant MFA is on and the user is not a member" do
    ensure_customer_feature_module(customer, auth_module, status: :active,
                                   configuration: { "mfa_enabled" => true }.to_json)
    admin = create(:user, :admin, customer: customer, email: "admin-mfa@example.com", password: "password123")

    result = call(email: admin.email, password: "password123")
    expect(result.next_action).to eq(:mfa_setup_required)
    expect(result.mfa_verified).to be(false)
  end

  it "does not force tenant MFA enrollment on members" do
    ensure_customer_feature_module(customer, auth_module, status: :active,
                                   configuration: { "mfa_enabled" => true }.to_json)
    member = create(:user, :member, customer: customer, email: "member-mfa@example.com", password: "password123")

    result = call(email: member.email, password: "password123")
    expect(result.next_action).to eq(:authenticated)
    expect(result.mfa_verified).to be(true)
  end

  it "requires tenant MFA after replacing a member's reserved role with admin" do
    ensure_customer_feature_module(customer, auth_module, status: :active,
                                   configuration: { "mfa_enabled" => true }.to_json)
    admin = create(:user, :member, customer: customer, email: "promoted-mfa@example.com", password: "password123")
    admin_role = customer.roles.system.find_by!(key: "admin")
    expect(UserRoles::Operation::Assign.call(user: admin, role_ids: [admin_role.id])).to be_success

    result = call(email: admin.email, password: "password123")
    expect(result.next_action).to eq(:mfa_setup_required)
    expect(result.user.reserved_role_keys).to eq(["admin"])
  end

  it "returns :mfa_required for an MFA-enforced user" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    result = call(email: "alice@example.com", password: "password123")
    expect(result.next_action).to eq(:mfa_required)
  end

  it "returns :mfa_setup_required for a user with otp_secret but no enforcement" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: false)
    result = call(email: "alice@example.com", password: "password123")
    expect(result.next_action).to eq(:mfa_setup_required)
  end

  it "increments failed_attempts on a wrong password (lockable)" do
    expect { call(email: "alice@example.com", password: "wrong") }
      .to change { user.reload.failed_attempts }.by(1)
  end

  it "resets failed_attempts on a successful sign-in" do
    user.update!(failed_attempts: 3)
    call(email: "alice@example.com", password: "password123")
    expect(user.reload.failed_attempts).to eq(0)
  end

  # .complete is the passwordless first factor (confirmation click, emailed
  # sign-in link). It replaces the PASSWORD only — a mailbox is one factor, so
  # every second-factor rule that applies to .call applies here identically.
  # These examples replaced an earlier set that asserted MFA was skipped for
  # everyone except the platform owner; that carve-out let mailbox access alone
  # defeat an enrolled TOTP, and has been removed.
  describe ".complete" do
    it "returns :authenticated without checking the password" do
      result = described_class.complete(user: user)
      expect(result.success?).to be(true)
      expect(result.next_action).to eq(:authenticated)
    end

    it "returns :invalid_credentials when authentication is disabled" do
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).delete_all
      result = described_class.complete(user: user)
      expect(result.success?).to be(false)
      expect(result.next_action).to eq(:invalid_credentials)
    end

    it "returns :invalid_credentials for a nil user" do
      result = described_class.complete(user: nil)
      expect(result.success?).to be(false)
      expect(result.next_action).to eq(:invalid_credentials)
    end

    it "returns :invalid_credentials for a locked account" do
      user.update!(locked_at: Time.current, failed_attempts: Devise.maximum_attempts)
      result = described_class.complete(user: user)
      expect(result.success?).to be(false)
      expect(result.next_action).to eq(:invalid_credentials)
    end

    it "returns :invalid_credentials for a deactivated account" do
      user.update!(status: :inactive)
      result = described_class.complete(user: user)
      expect(result.success?).to be(false)
      expect(result.next_action).to eq(:invalid_credentials)
    end

    it "still requires TOTP for an MFA-enforced non-owner" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      result = described_class.complete(user: user)
      expect(result.next_action).to eq(:mfa_required)
      expect(result.mfa_verified).to be(false)
    end

    it "still requires finishing setup for a non-owner with an unenforced secret" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: false)
      result = described_class.complete(user: user)
      expect(result.next_action).to eq(:mfa_setup_required)
      expect(result.mfa_verified).to be(false)
    end

    it "requires MFA for the platform owner when TOTP is enforced" do
      owner = find_or_create_platform_owner
      ensure_customer_feature_module(owner.customer, auth_module, status: :active)
      owner.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      result = described_class.complete(user: owner)
      expect(result.next_action).to eq(:mfa_required)
      expect(result.mfa_verified).to be(false)
    end

    it "honours a trusted device for an MFA-enforced user" do
      user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
      _record, raw = Authentication::TrustedDevice.issue!(user: user, ip: nil, user_agent: nil)

      result = described_class.complete(user: user, trusted_device_token: raw)
      expect(result.next_action).to eq(:authenticated)
      expect(result.mfa_verified).to be(true)
    end
  end
end
