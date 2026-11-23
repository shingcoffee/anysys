# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Signature do
  let(:payload) { '{"id":1}' }
  let(:secret) { "whsec_test" }
  let(:ctx) { { errors: [], error_details: [] } }

  def digest(algorithm: "sha256", encoding: "hex", data: payload)
    FlowchartRuntime::Crypto.hmac(algorithm, key: secret, data: data, encoding: encoding)
  end

  def verify(**overrides)
    described_class.verify(
      ctx,
      payload: payload,
      signature: digest,
      secret: secret,
      algorithm: "sha256",
      encoding: "hex",
      prefix: "",
      signed_payload: "body",
      timestamp: nil,
      separator: ".",
      tolerance: 300,
      on_invalid: "fail",
      **overrides
    )
  end

  it "accepts a matching hex HMAC" do
    expect(verify).to be(true)
    expect(ctx[:errors]).to eq([])
  end

  it "accepts a matching HMAC when optional kwargs use their defaults" do
    expect(
      described_class.verify(ctx, payload: payload, signature: digest, secret: secret)
    ).to be(true)
  end

  it "accepts a matching base64 HMAC" do
    signature = digest(encoding: "base64")
    expect(verify(signature: signature, encoding: "base64")).to be(true)
  end

  it "accepts sha512 and sha1 digests" do
    %w[sha512 sha1].each do |algorithm|
      ctx[:errors] = []
      signature = digest(algorithm: algorithm)
      expect(verify(signature: signature, algorithm: algorithm)).to be(true), algorithm
    end
  end

  it "strips a GitHub-style prefix" do
    expect(verify(signature: "sha256=#{digest}", prefix: "sha256=")).to be(true)
  end

  it "accepts any Stripe v1= candidate" do
    other = digest(data: "nope")
    header = "t=1700000000,v1=#{digest},v1=#{other}"
    expect(verify(signature: header)).to be(true)
  end

  it "fails with verify_signature.invalid when no candidate matches" do
    expect(verify(signature: "deadbeef")).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("verify_signature.invalid")
    expect(ctx[:errors].first).to eq(I18n.t("flowchart_runtime.errors.verify_signature.invalid"))
  end

  it "returns false without failing when on_invalid is flag" do
    expect(verify(signature: "deadbeef", on_invalid: "flag")).to be(false)
    expect(ctx[:errors]).to eq([])
  end

  it "fails with verify_signature.missing_secret when the secret is blank" do
    expect(verify(secret: "")).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("verify_signature.missing_secret")
  end

  it "fails with verify_signature.expired when the timestamp is too old" do
    travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
      ts = 1.hour.ago.to_i
      data = "#{ts}.#{payload}"
      expect(verify(
        signature: digest(data: data),
        signed_payload: "timestamp_body",
        timestamp: ts,
        separator: ".",
        tolerance: 300
      )).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("verify_signature.expired")
    end
  end

  it "returns false without failing for an expired timestamp when on_invalid is flag" do
    travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
      ts = 1.hour.ago.to_i
      expect(verify(
        signature: digest(data: "#{ts}.#{payload}"),
        signed_payload: "timestamp_body",
        timestamp: ts,
        on_invalid: "flag"
      )).to be(false)
      expect(ctx[:errors]).to eq([])
    end
  end

  it "still fails for a missing secret when on_invalid is flag" do
    expect(verify(secret: "", on_invalid: "flag")).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("verify_signature.missing_secret")
  end

  it "accepts a timestamp within tolerance, including millisecond values" do
    travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
      ts_ms = (Time.now.to_f * 1000).to_i
      data = "#{ts_ms}.#{payload}"
      expect(verify(
        signature: digest(data: data),
        signed_payload: "timestamp_body",
        timestamp: ts_ms,
        separator: ".",
        tolerance: 300
      )).to be(true)
    end
  end

  it "skips the age check when tolerance is 0" do
    ts = 1_700_000_000
    data = "#{ts}.#{payload}"
    expect(verify(
      signature: digest(data: data),
      signed_payload: "timestamp_body",
      timestamp: ts,
      separator: ".",
      tolerance: 0
    )).to be(true)
  end
end
