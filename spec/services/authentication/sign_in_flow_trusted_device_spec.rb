# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::SignInFlow, "trusted device" do
  let(:customer) do
    Customer.find_or_create_by!(id: 81721200) { |c| c.name = "Plat"; c.industry = :technology; c.tier = :basic }
  end
  let!(:user) do
    create_mfa_user(customer: customer, email: "a@x.com", first_name: "A", last_name: "B")
  end

  # Creates a confirmed user with an OTP secret and MFA enforced.
  def create_mfa_user(customer:, email:, first_name:, last_name:)
    Authentication::User.create!(
      customer_id: customer.id, email: email, password: "Password!234",
      first_name: first_name, last_name: last_name, confirmed_at: Time.current
    ).tap do |u|
      u.generate_otp_secret!
      u.enable_mfa!
    end
  end

  before do
    auth_module = ::FeatureModules::Module.find_by!(key: "authentication")
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  def call(token)
    described_class.call(email: "a@x.com",
      password: "Password!234", trusted_device_token: token)
  end

  it "skips MFA and marks verified when a valid trusted token is presented" do
    _record, raw = Authentication::TrustedDevice.issue!(user: user, ip: nil, user_agent: nil)
    result = call(raw)
    expect(result.next_action).to eq(:authenticated)
    expect(result.mfa_verified).to be(true)
  end

  it "still requires MFA for a missing or invalid token" do
    result = call(nil)
    expect(result.next_action).to eq(:mfa_required)
    expect(result.mfa_verified).to be(false)

    expect(call("garbage").next_action).to eq(:mfa_required)
  end

  it "still requires MFA for an expired token" do
    record, raw = Authentication::TrustedDevice.issue!(user: user, ip: nil, user_agent: nil)
    record.update_column(:expires_at, 1.minute.ago)
    expect(call(raw).next_action).to eq(:mfa_required)
  end

  it "never lets a token issued for one tenant satisfy MFA for another tenant" do
    other_customer = Customer.find_or_create_by!(id: 96546124) { |c| c.name = "Other"; c.industry = :technology; c.tier = :basic }
    ensure_customer_feature_module(other_customer, ::FeatureModules::Module.find_by!(key: "authentication"), status: :active)
    other_user = create_mfa_user(customer: other_customer, email: "z@x.com", first_name: "Z", last_name: "Q")
    _record, raw = Authentication::TrustedDevice.issue!(user: other_user, ip: nil, user_agent: nil)

    # raw belongs to other_user; presenting it for `user` must not skip MFA
    result = described_class.call(email: "a@x.com",
      password: "Password!234", trusted_device_token: raw)
    expect(result.next_action).to eq(:mfa_required)
  end
end
