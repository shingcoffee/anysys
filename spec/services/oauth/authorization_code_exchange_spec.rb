# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::AuthorizationCodeExchange do
  let(:user) { create(:user, :admin, customer: create(:customer)) }
  let(:verifier) { "a" * 43 }
  let(:grant) do
    Doorkeeper.config.access_grant_model.create!(
      application: Oauth::DesktopClient.ensure!, resource_owner_id: user.id,
      expires_in: Oauth::Protocol::AUTHORIZATION_CODE_TTL.to_i,
      redirect_uri: "http://127.0.0.1/callback", scopes: Oauth::Protocol::SCOPE,
      code_challenge: Doorkeeper.config.access_grant_model.generate_code_challenge(verifier),
      code_challenge_method: "S256"
    )
  end

  it "exchanges a valid PKCE grant through the real Doorkeeper strategy" do
    code = grant.plaintext_token
    request = Doorkeeper::OAuth::AuthorizationCodeRequest.new(
      Doorkeeper.config, grant, Doorkeeper::OAuth::Client.find(Oauth::Protocol::CLIENT_ID),
      redirect_uri: grant.redirect_uri, code_verifier: verifier
    )

    response = described_class.call(code: code) { request.authorize }

    expect(response).to be_a(Doorkeeper::OAuth::TokenResponse)
    expect(grant.reload).to be_revoked
    expect(request.access_token).not_to be_revoked
    expect(request.access_token.resource_owner_id).to eq(user.id)
    expect(request.access_token.family_started_at).to be_present
  end

  it "rejects a grant looked up before a credential change when exchange resumes afterwards" do
    code = grant.plaintext_token
    stale = Doorkeeper.config.access_grant_model.find(grant.id)
    user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")
    allow(Doorkeeper.config.access_grant_model).to receive(:by_token).with(code).and_return(stale)

    expect { described_class.call(code: code) { raise "exchange must not run" } }
      .to raise_error(Doorkeeper::Errors::InvalidGrant)
    expect(grant.reload).to be_revoked
  end

  it "lets Doorkeeper handle an unknown code through its usual invalid-grant response" do
    expect(described_class.call(code: "unknown") { :invalid_grant_response }).to eq(:invalid_grant_response)
  end

  it "rejects an expired grant with a response-bearing InvalidGrant error" do
    code = grant.plaintext_token
    grant.update!(created_at: 20.minutes.ago)

    expect { described_class.call(code: code) { raise "exchange must not run" } }
      .to raise_error(Doorkeeper::Errors::InvalidGrant) { |error|
        expect(error.response.status).to eq(:bad_request)
        expect(error.response.body[:error]).to eq(:invalid_grant)
      }
  end

  it "rejects a grant when its account lookup no longer resolves an owner" do
    code = grant.plaintext_token
    owner_id = grant.resource_owner_id
    allow(Authentication::User).to receive(:find_by).with(id: owner_id).and_return(nil)

    expect { described_class.call(code: code) { raise "exchange must not run" } }
      .to raise_error(Doorkeeper::Errors::InvalidGrant) { |error|
        expect(error.response.status).to eq(:bad_request)
        expect(error.response.body[:error]).to eq(:invalid_grant)
      }
  end

  it "rolls an exchange's writes back before propagating its error" do
    code = grant.plaintext_token
    expect {
      described_class.call(code: code) do
        grant.revoke
        raise Doorkeeper::Errors::InvalidGrant.new(
          Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)
        )
      end
    }.to raise_error(Doorkeeper::Errors::InvalidGrant)
    expect(grant.reload).not_to be_revoked
  end
end
