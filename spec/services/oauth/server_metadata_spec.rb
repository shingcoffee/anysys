# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::ServerMetadata do
  subject(:body) do
    described_class.call(instance_double(ActionDispatch::Request, base_url: "https://app.example"))
  end

  it "lists PKCE S256 and the public endpoints" do
    expect(body[:issuer]).to eq("https://app.example")
    expect(body[:authorization_endpoint]).to eq("https://app.example/oauth/authorize")
    expect(body[:code_challenge_methods_supported]).to eq(%w[S256])
    expect(body[:token_endpoint_auth_methods_supported]).to eq(%w[none])
  end

  it "advertises only the response mode the loopback handoff can deliver" do
    expect(body[:response_types_supported]).to eq(%w[code])
    expect(body[:response_modes_supported]).to eq(%w[query])
  end

  it "declares the UI locales the authorize page can render" do
    expect(body[:ui_locales_supported]).to eq(%w[en zh-CN])
  end

  it "tells clients the authorization response carries no iss (RFC 9207)" do
    expect(body[:authorization_response_iss_parameter_supported]).to be false
  end

  it "omits claims this server does not implement" do
    expect(body.keys).not_to include(:jwks_uri, :registration_endpoint,
                                     :id_token_signing_alg_values_supported)
  end

  it "pins issuer to APP_HOST instead of the request Host" do
    ClimateControl.modify(APP_HOST: "canonical.example") do
      body = described_class.call(
        instance_double(ActionDispatch::Request, base_url: "https://evil.example")
      )
      expect(body[:issuer]).to eq("https://canonical.example")
      expect(body[:authorization_endpoint]).to eq("https://canonical.example/oauth/authorize")
    end
  end

  it "keeps an explicit scheme on APP_HOST" do
    ClimateControl.modify(APP_HOST: "https://canonical.example/") do
      body = described_class.call(
        instance_double(ActionDispatch::Request, base_url: "http://evil.example")
      )
      expect(body[:issuer]).to eq("https://canonical.example")
    end
  end
end
