# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Jwt do
  let(:secret) { "test-secret" }
  let(:payload) { { "sub" => "user-1", "exp" => 1.hour.from_now.to_i } }

  describe ".issue / .verify" do
    it "issues a token with expiry and verifies nested claims" do
      token = described_class.issue({ "user" => { "role" => "admin" } }, secret, expires_in: 3600,
                                    issuer: "iss", claims: { "aud" => "api" })
      payload = described_class.verify(token, secret, algorithms: ["HS256"], iss: "iss", aud: "api",
                                         required_claims: { "user.role" => "admin" })
      expect(payload["iss"]).to eq("iss")
      expect(payload["user"]).to eq("role" => "admin")
    end

    it "writes sub and iat when requested" do
      travel_to(Time.utc(2026, 1, 1)) do
        token = described_class.issue({}, secret, subject: "user-9", issued_at: true)
        payload = described_class.verify(token, secret, algorithms: ["HS256"])
        expect(payload).to include("sub" => "user-9", "iat" => Time.current.to_i)
      end
    end

    it "raises setup errors from verify_or_nil instead of reporting an invalid token" do
      token = described_class.encode({ "sub" => "1" }, secret)
      expect { described_class.verify_or_nil(token, "", algorithms: ["HS256"]) }
        .to raise_error(FlowchartRuntime::Jwt::Error, "secret is required")
      expect { described_class.verify_or_nil(token, secret, algorithms: ["none"]) }
        .to raise_error(FlowchartRuntime::Jwt::Error, "unsupported algorithm")
      expect(described_class.verify_or_nil(token, secret, algorithms: ["HS256"], required_claims: { "role" => nil })).to be_nil
    end

    it "returns nil from verify_or_nil when the token is invalid" do
      expect(described_class.verify_or_nil("nope", secret, algorithms: ["HS256"])).to be_nil
    end

    it "rejects an invalid duration" do
      expect { described_class.issue({}, secret, expires_in: "nope") }
        .to raise_error(described_class::Error, /invalid expiry/)
    end
  end

  describe ".encode" do
    it "returns a signed token string" do
      token = described_class.encode(payload, secret)
      expect(token).to be_a(String)
      expect(token.split(".").length).to eq(3)
    end

    it "supports custom algorithm and headers" do
      token = described_class.encode(payload, secret, algorithm: "HS512", headers: { kid: "key-1" })
      decoded = described_class.decode(token, secret, algorithms: ["HS512"])
      expect(decoded["sub"]).to eq("user-1")
    end

    it "normalizes PEM strings for RS256 encode and decode" do
      key = OpenSSL::PKey::RSA.generate(2048)
      token = described_class.encode(payload, key.to_pem, algorithm: "RS256")

      expect(described_class.decode(token, key.public_key.to_pem, algorithms: ["RS256"]))
        .to include("sub" => "user-1")
    end

    it "wraps invalid RS256 PEM as Error" do
      expect { described_class.encode(payload, "not-a-pem", algorithm: "RS256") }
        .to raise_error(described_class::Error)
    end

    it "raises Error for unsupported algorithms" do
      expect { described_class.encode(payload, secret, algorithm: "none") }
        .to raise_error(FlowchartRuntime::Jwt::Error, /unsupported algorithm/)
    end
  end

  describe ".decode" do
    let(:token) { described_class.encode(payload, secret) }

    it "round-trips encode/decode" do
      expect(described_class.decode(token, secret)).to include("sub" => "user-1")
    end

    it "raises Error for tampered tokens" do
      parts = token.split(".")
      tampered = [parts[0], parts[1], "bogus"].join(".")
      expect { described_class.decode(tampered, secret) }
        .to raise_error(FlowchartRuntime::Jwt::Error)
    end

    it "raises Error when no allowed algorithm matches" do
      hs512_token = described_class.encode(payload, secret, algorithm: "HS512")
      expect { described_class.decode(hs512_token, secret, algorithms: ["HS256"]) }
        .to raise_error(FlowchartRuntime::Jwt::Error)
    end

    it "raises Error for unsupported algorithms in the allow-list" do
      expect { described_class.decode(token, secret, algorithms: ["none"]) }
        .to raise_error(FlowchartRuntime::Jwt::Error, /unsupported algorithm/)
    end

    it "passes through decode options such as leeway" do
      expired_payload = { "sub" => "user-1", "exp" => 1.hour.ago.to_i }
      expired_token = described_class.encode(expired_payload, secret)
      expect { described_class.decode(expired_token, secret) }
        .to raise_error(FlowchartRuntime::Jwt::Error)
      expect(described_class.decode(expired_token, secret, leeway: 7200)).to include("sub" => "user-1")
    end
  end
end
