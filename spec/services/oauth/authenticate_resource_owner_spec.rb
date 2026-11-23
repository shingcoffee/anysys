# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::AuthenticateResourceOwner do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }

  before { allow(FeatureModules::Module).to receive(:enabled?).and_return(true) }

  def decide(candidate = user, mfa_verified: false)
    described_class.call(user: candidate, mfa_verified: mfa_verified)
  end

  it "authorizes a complete session" do
    result = decide
    expect(result).to be_authorized
    expect(result.user).to eq(user)
  end

  it "sends anonymous traffic to sign-in" do
    result = decide(nil)
    expect(result.next_action).to eq(:sign_in)
    expect(result.user).to be_nil
  end

  it "sends inactive users to sign-in" do
    user.inactive!
    expect(decide.next_action).to eq(:sign_in)
  end

  it "sends users to sign-in when the authentication module is off" do
    allow(FeatureModules::Module).to receive(:enabled?)
      .with(key: "authentication", customer_id: customer.id).and_return(false)
    expect(decide.next_action).to eq(:sign_in)
  end

  it "sends enforced-MFA users to verification, carrying the user for the tenant path" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    result = decide
    expect(result.next_action).to eq(:mfa_verify)
    expect(result.user).to eq(user)
  end

  it "sends a half-finished enrollment back to setup" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: false)
    expect(decide.next_action).to eq(:mfa_setup)
  end

  it "authorizes once the session has cleared MFA" do
    user.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    expect(decide(mfa_verified: true)).to be_authorized
  end

  it "sends admins to MFA setup when the tenant requires enrollment" do
    allow(Authentication::Settings).to receive(:for).with(customer.id)
      .and_return(instance_double(Authentication::Settings, mfa_enabled?: true))
    expect(decide.next_action).to eq(:mfa_setup)
  end

  it "does not force tenant MFA setup on members" do
    member = create(:user, :member, customer: customer)
    allow(Authentication::Settings).to receive(:for).with(customer.id)
      .and_return(instance_double(Authentication::Settings, mfa_enabled?: true))
    expect(decide(member).next_action).to eq(:authorized)
  end
end
