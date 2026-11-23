# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::VerifySignatureGenerator do
  let(:context) { {} }
  let(:base) do
    {
      "payloadVariable" => "raw_body",
      "signatureVariable" => "params.signature",
      "secretSource" => "ctx",
      "secretVariable" => "webhook_secret",
      "resultVar" => "signature_valid"
    }
  end
  let(:element) { { "config" => base } }
  let(:payload) { '{"id":1}' }
  let(:secret) { "whsec_test" }

  it_behaves_like "a code generator"

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def hmac(data = payload, algorithm: "sha256", encoding: "hex")
    FlowchartRuntime::Crypto.hmac(algorithm, key: secret, data: data, encoding: encoding)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:signature_valid] = FlowchartRuntime::Signature.verify(
          ctx,
          payload: ctx[:raw_body],
          signature: FlowchartRuntime::Step.dig(ctx[:params], :signature),
          secret: Rails.application.credentials.dig(:webhook_secret)
        )
      end
    RUBY
  end

  it "generates a ctx secret lookup" do
    config = described_class.sample_input.merge("secretSource" => "ctx", "secretVariable" => "webhook_secret")
    expect(generated_step(config)).to include("secret: ctx[:webhook_secret]")
  end

  it "generates timestamp_body verification" do
    config = described_class.sample_input.merge(
      "signedPayload" => "timestamp_body", "timestampVariable" => "params.timestamp"
    )
    src = generated_step(config)
    expect(src).to include('signed_payload: "timestamp_body"')
    expect(src).to include("timestamp: FlowchartRuntime::Step.dig(ctx[:params], :timestamp)")
  end

  it "emits Signature.verify and resolves secrets without a literal secret" do
    src = body
    expect(src).to include("FlowchartRuntime::Signature.verify")
    expect(src).to include("ctx[:webhook_secret]")
    expect(src).not_to include("whsec_")
    expect(body(base.merge("secretSource" => "credentials", "keyPath" => "webhooks.signing_secret")))
      .to include("Rails.application.credentials.dig(:webhooks, :signing_secret)")
    expect(body(base.merge("secretSource" => "env", "keyPath" => "WEBHOOK_SECRET")))
      .to include('ENV.fetch("WEBHOOK_SECRET", nil)')
  end

  it "rejects an invalid env keyPath" do
    msgs = errors(base.merge("secretSource" => "env", "keyPath" => "not-a-name"))
    expect(msgs.map(&:code)).to include(:invalid_env_name)
  end

  it "requires keyPath when the secret comes from credentials" do
    msgs = errors(described_class.sample_input.merge("secretSource" => "credentials", "keyPath" => ""))
    expect(msgs.map(&:code)).to include(:required)
    expect(msgs.map(&:field)).to include("keyPath")
  end

  it "does not fall back to secret_key_base when keyPath is empty" do
    src = body(base.merge("secretSource" => "credentials", "keyPath" => "webhooks.signing_secret"))
    expect(src).to include("Rails.application.credentials.dig(:webhooks, :signing_secret)")
    expect(src).not_to include("secret_key_base")
  end

  describe "behaviour" do
    let(:ctx) do
      {
        raw_body: payload,
        params: { signature: hmac, timestamp: Time.utc(2026, 1, 1, 12, 0, 0).to_i },
        webhook_secret: secret,
        errors: [],
        error_details: []
      }
    end

    it "accepts a matching HMAC and writes signature_valid" do
      result = execute(base, ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:signature_valid]).to be(true)
    end

    it "fails the step when the signature does not match" do
      ctx[:params] = { signature: "deadbeef" }
      result = execute(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("verify_signature.invalid")
    end

    it "flags an invalid signature and continues when onInvalid is flag" do
      ctx[:params] = { signature: "deadbeef" }
      result = execute(base.merge("onInvalid" => "flag"), ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:signature_valid]).to be(false)
      expect(ctx[:errors]).to eq([])
    end

    it "fails when the signing secret is missing" do
      ctx[:webhook_secret] = ""
      result = execute(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("verify_signature.missing_secret")
    end

    it "verifies a timestamp_body payload within tolerance" do
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) do
        ts = Time.current.to_i
        ctx[:params] = { signature: hmac("#{ts}.#{payload}"), timestamp: ts }
        result = execute(base.merge("signedPayload" => "timestamp_body", "timestampVariable" => "params.timestamp"), ctx)
        expect(result[:outcome]).to be(true)
        expect(ctx[:signature_valid]).to be(true)
      end
    end
  end
end
