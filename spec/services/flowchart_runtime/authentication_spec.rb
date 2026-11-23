# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Authentication do
  include FlowchartAuthenticationHelpers

  let(:user) { create(:user) }

  def principal(request, customer_id: user.customer_id)
    described_class.session(context: described_class.from_request(request), customer_id: customer_id)
  end

  it "uses the application's salted Devise session serializer on a fresh Warden proxy" do
    request = warden_round_trip(user)
    expect(request.env["rack.session"]["warden.user.user.key"]).to eq(Authentication::User.serialize_into_session(user))
    expect(principal(request)).to eq(user)
  end

  it "rejects and removes a session whose authenticatable_salt changed" do
    request = warden_round_trip(user)
    user.update!(password: "changed-password123")
    expect(principal(request)).to be_nil
    expect(request.env["rack.session"]).not_to have_key("warden.user.user.key")
  end

  it "honors Warden logout and does not run a new authentication strategy" do
    request = warden_round_trip(user)
    request.env["warden"].logout(:user)
    expect(principal(request)).to be_nil
  end

  it "honors the Devise timeout hook and returns no principal when it throws :warden" do
    request = warden_round_trip(user)
    request.env["rack.session"]["warden.user.user.session"]["last_request_at"] = 1.hour.ago.to_i
    expect(principal(request)).to be_nil
    expect(request.env["rack.session"]).not_to have_key("warden.user.user.key")
  end

  it "honors the Devise activation hook when a previously signed-in account is locked" do
    request = warden_round_trip(user)
    user.lock_access!
    expect(principal(request)).to be_nil
    expect(request.env["rack.session"]).not_to have_key("warden.user.user.key")
  end

  it "rejects a deleted session user" do
    request = warden_round_trip(user)
    user.destroy!
    expect(principal(request)).to be_nil
  end

  it "rejects foreign or absent tenant context without changing the signed-in account" do
    request = warden_round_trip(user)
    expect(principal(request, customer_id: create(:customer).id)).to be_nil
    expect(principal(request, customer_id: nil)).to be_nil
    expect(request.env["warden"].user(:user)).to eq(user)
  end

  it "does not turn serialized IDs or JSON-shaped authentication input into a principal" do
    expect(described_class.session(context: { user_id: user.id }, customer_id: user.customer_id)).to be_nil
    expect(principal(warden_request("user_id" => user.id))).to be_nil
    expect(principal(nil)).to be_nil
    expect(principal({ "warden" => { "user_id" => user.id } })).to be_nil
  end

  it "keeps the request and user attributes out of authentication context inspection" do
    context = described_class.from_request(warden_round_trip(user))
    expect(context).to be_frozen
    expect(context.inspect).to eq("#<FlowchartRuntime::Authentication>")
  end

  it "does not count a password attempt for a user outside the target tenant" do
    expect {
      expect(described_class.password(user: user, password: "wrong", customer_id: create(:customer).id)).to be_nil
    }.not_to change { user.reload.failed_attempts }
  end

  it "matches bearer, basic and custom tokens in constant time" do
    expect(described_class.token(raw: "Bearer secret", expected: "secret")).to eq("secret")
    expect(described_class.token(raw: "Basic secret", expected: "secret", type: "basic")).to eq("secret")
    expect(described_class.token(raw: "Bearer secret", expected: "Bearer secret", type: "custom")).to eq("Bearer secret")
    expect(described_class.token(raw: "Bearer wrong", expected: "secret")).to be_nil
    expect(described_class.token(raw: "Bearer ", expected: "")).to be_nil
  end

  it "matches API keys and rejects blanks" do
    expect(described_class.api_key(raw: "k", expected: "k")).to be(true)
    expect(described_class.api_key(raw: "k", expected: "x")).to be_nil
    expect(described_class.api_key(raw: "", expected: "")).to be_nil
  end
end
