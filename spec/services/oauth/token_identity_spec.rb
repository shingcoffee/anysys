# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::TokenIdentity do
  let_it_be(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:application) { Oauth::DesktopClient.ensure! }

  def issue(app: application, scopes: Oauth::Protocol::SCOPE, owner: user, **attrs)
    Oauth::AccessToken.create_for(
      application: app,
      resource_owner: owner,
      scopes: scopes,
      expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i,
      **attrs
    )
  end

  it "resolves the active owner of a live first-party token" do
    expect(described_class.call(issue)).to eq(user)
  end

  it "rejects a nil token" do
    expect(described_class.call(nil)).to be_nil
  end

  it "rejects a revoked token" do
    token = issue
    token.revoke
    expect(described_class.call(token)).to be_nil
  end

  it "rejects an expired token" do
    expect(described_class.call(issue(expires_in: -1))).to be_nil
  end

  it "rejects a token without the profile scope" do
    expect(described_class.call(issue(scopes: ""))).to be_nil
  end

  it "rejects a token issued to another OAuth application" do
    other = Doorkeeper::Application.create!(
      name: "Other", uid: "other-client", redirect_uri: "http://127.0.0.1/callback",
      confidential: false, scopes: Oauth::Protocol::SCOPE
    )
    expect(described_class.call(issue(app: other))).to be_nil
  end

  it "rejects a token whose owner was deactivated" do
    token = issue
    user.inactive!
    expect(described_class.call(token)).to be_nil
  end

  it "rejects a token whose owner is locked under Devise eligibility" do
    token = issue
    user.lock_access!

    expect(described_class.call(token)).to be_nil
  end

  it "rejects a token whose owner is unconfirmed" do
    token = issue
    user.update!(confirmed_at: nil)

    expect(described_class.call(token)).to be_nil
  end

  it "rejects a token whose owner no longer exists" do
    token = issue
    allow(Authentication::User).to receive(:find_by).with(id: token.resource_owner_id).and_return(nil)
    expect(described_class.call(token)).to be_nil
  end
end
