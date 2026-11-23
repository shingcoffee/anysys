# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vendor::AliyunRpc do
  describe ".common_params" do
    it "builds the RPC common parameter set with stringified values" do
      allow(SecureRandom).to receive(:uuid).and_return("nonce-fixed")
      allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 12, 12, 0, 0))

      params = described_class.common_params(
        access_key_id: :AKID, region_id: "cn-shanghai", version: "2019-02-28"
      )

      expect(params).to eq(
        "AccessKeyId"      => "AKID",
        "Format"           => "JSON",
        "RegionId"         => "cn-shanghai",
        "SignatureMethod"  => "HMAC-SHA1",
        "SignatureNonce"   => "nonce-fixed",
        "SignatureVersion" => "1.0",
        "Timestamp"        => "2026-05-12T12:00:00Z",
        "Version"          => "2019-02-28"
      )
    end

    it "generates a fresh nonce per call so a signed request is not replayable" do
      first  = described_class.common_params(access_key_id: "a", region_id: "r", version: "v")
      second = described_class.common_params(access_key_id: "a", region_id: "r", version: "v")
      expect(first["SignatureNonce"]).not_to eq(second["SignatureNonce"])
    end
  end

  describe ".encode" do
    it "applies Aliyun's RFC 3986 fixups on top of CGI.escape" do
      expect(described_class.encode("a b")).to eq("a%20b")
      expect(described_class.encode("a*b")).to eq("a%2Ab")
      expect(described_class.encode("a~b")).to eq("a~b")
      expect(described_class.encode("/")).to eq("%2F")
    end

    it "stringifies non-string input" do
      expect(described_class.encode(nil)).to eq("")
      expect(described_class.encode(42)).to eq("42")
    end
  end

  describe ".canonical_query" do
    it "sorts by parameter name and percent-encodes both sides" do
      expect(described_class.canonical_query({ "b" => "2", "a" => "x y" })).to eq("a=x%20y&b=2")
    end
  end

  describe ".string_to_sign" do
    it "prefixes the HTTP verb and the encoded root path" do
      expect(described_class.string_to_sign({ "a" => "1" })).to eq("POST&%2F&a%3D1")
    end

    it "honours a non-default verb" do
      expect(described_class.string_to_sign({ "a" => "1" }, http_verb: "GET")).to start_with("GET&")
    end
  end

  # Golden test — pins the exact HMAC-SHA1 output for a controlled input so any
  # accidental change to the encoding rules or to the HMAC key format (the
  # trailing "&" on the secret) breaks loudly. All three Aliyun adapters
  # delegate here, so this locks the signature they produce.
  describe ".sign" do
    let(:params) do
      {
        "AccessKeyId"      => "testid",
        "Action"           => "SendSms",
        "Format"           => "JSON",
        "PhoneNumbers"     => "+8613800138000",
        "RegionId"         => "cn-hangzhou",
        "SignName"         => "TestCo",
        "SignatureMethod"  => "HMAC-SHA1",
        "SignatureNonce"   => "fixed-nonce",
        "SignatureVersion" => "1.0",
        "TemplateCode"     => "SMS_1",
        "TemplateParam"    => '{"code":"1234"}',
        "Timestamp"        => "2026-04-28T00:00:00Z",
        "Version"          => "2017-05-25"
      }
    end

    it "produces a deterministic signature for known inputs" do
      expect(described_class.sign(params, secret: "testsecret")["Signature"])
        .to eq("RWzRGS71aY1iTehsb3VuHfHAJwY=")
    end

    it "matches the algorithm recomputed independently" do
      sorted = params.sort.map { |k, v|
        [ k, v ].map { |s| CGI.escape(s.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~") }.join("=")
      }.join("&")
      to_sign  = "POST&#{CGI.escape('/')}&#{CGI.escape(sorted).gsub('+', '%20').gsub('*', '%2A').gsub('%7E', '~')}"
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "testsecret&", to_sign))

      expect(described_class.signature(params, secret: "testsecret")).to eq(expected)
    end

    it "leaves the caller's params untouched and returns a merged copy" do
      signed = described_class.sign(params, secret: "testsecret")
      expect(params).not_to have_key("Signature")
      expect(signed.except("Signature")).to eq(params)
    end

    it "changes the signature when the secret changes" do
      expect(described_class.signature(params, secret: "a"))
        .not_to eq(described_class.signature(params, secret: "b"))
    end
  end
end
