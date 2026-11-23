# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::Protocol do
  describe ".loopback_redirect?" do
    it "accepts IPv4 loopback callback URIs with query params" do
      expect(described_class.loopback_redirect?("http://127.0.0.1:8765/callback?code=a&state=b")).to be true
    end

    it "accepts IPv6 loopback callback URIs" do
      expect(described_class.loopback_redirect?("http://[::1]:41832/callback?code=a")).to be true
    end

    # Delegating the host test to Doorkeeper's URIChecker (IPAddr#loopback?)
    # covers the whole 127.0.0.0/8 range, as RFC 8252 §7.3 expects.
    it "accepts the rest of the 127.0.0.0/8 loopback range" do
      expect(described_class.loopback_redirect?("http://127.0.0.5:8765/callback")).to be true
    end

    it "rejects https, non-loopback hosts, and the wrong path" do
      expect(described_class.loopback_redirect?("https://127.0.0.1/callback")).to be false
      expect(described_class.loopback_redirect?("http://evil.example/callback")).to be false
      expect(described_class.loopback_redirect?("http://127.0.0.1/other")).to be false
    end

    it "rejects a public address that merely looks loopback-ish" do
      expect(described_class.loopback_redirect?("http://127.0.0.1.evil.example/callback")).to be false
      expect(described_class.loopback_redirect?("http://128.0.0.1/callback")).to be false
    end

    it "rejects unparseable values and hostless URIs" do
      expect(described_class.loopback_redirect?("not a uri")).to be false
      expect(described_class.loopback_redirect?(nil)).to be false
      expect(described_class.loopback_redirect?(":")).to be false
      expect(described_class.loopback_redirect?("http:/callback")).to be false
    end
  end

  describe "token lifetimes" do
    it "is the single source of truth Doorkeeper is configured from" do
      expect(Doorkeeper.config.access_token_expires_in).to eq(described_class::ACCESS_TOKEN_TTL)
      expect(Doorkeeper.config.authorization_code_expires_in).to eq(described_class::AUTHORIZATION_CODE_TTL)
    end
  end
end
