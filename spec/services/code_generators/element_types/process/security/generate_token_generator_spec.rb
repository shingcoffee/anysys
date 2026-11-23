# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::GenerateTokenGenerator do
  let(:context) { {} }
  let(:base) do
    { "tokenType" => "jwt", "resultVar" => "token", "payloadVariable" => "payload", "secretVariable" => "secret",
      "secretSource" => "ctx", "algorithm" => "HS256" }
  end
  let(:element) { { "config" => base } }

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

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"generate_token.failed", FlowchartRuntime::Jwt::Error) do
          ctx[:token] = FlowchartRuntime::Jwt.issue(
            ctx[:payload],
            Rails.application.credentials.dig(:secret),
            expires_in: "1h",
            issued_at: true
          )
          true
        end
      end
    RUBY
  end

  it "generates a signed MessageVerifier payload" do
    config = described_class.sample_input.merge("tokenType" => "signed", "secretSource" => "ctx",
                                               "secretVariable" => "secret")
    expect(generated_step(config)).to include("FlowchartRuntime::Token.sign(")
    expect(generated_step(config)).to include("key: ctx[:secret]")
  end

  it "generates a numeric OTP" do
    expect(generated_step(described_class.sample_input.merge("tokenType" => "numeric_otp"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:token] = SecureRandom.random_number(10 ** 6).to_s.rjust(6, "0")
      end
    RUBY
  end

  describe "behaviour" do
    it "issues a verifiable JWT with expiry and claims" do
      travel_to(Time.utc(2026, 1, 1)) do
        ctx = { payload: { "sub" => "user-1" }.freeze, secret: "secret" }
        cfg = base.merge("expiresIn" => 3600, "issuer" => "issuer", "audience" => "api", "keyId" => "primary")
        expect(execute(cfg, ctx)[:outcome]).to be_truthy
        claims, header = JWT.decode(ctx[:token], "secret", true, algorithms: ["HS256"], iss: "issuer",
                                    verify_iss: true, aud: "api", verify_aud: true)
        expect(claims).to include("sub" => "user-1", "iss" => "issuer", "aud" => "api",
                                  "exp" => Time.current.to_i + 3600)
        expect(header["kid"]).to eq("primary")
      end
    end

    it "writes sub and iat when subject and includeIssuedAt are set" do
      travel_to(Time.utc(2026, 1, 1)) do
        ctx = { payload: {}, secret: "secret" }
        cfg = base.merge("subject" => "user-9", "includeIssuedAt" => true)
        expect(execute(cfg, ctx)[:outcome]).to be_truthy
        claims, = JWT.decode(ctx[:token], "secret", true, algorithms: ["HS256"])
        expect(claims).to include("sub" => "user-9", "iat" => Time.current.to_i)
      end
    end

    it "records a translated failure when the secret is missing" do
      ctx = { payload: {}, secret: nil, token: "stale" }
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not generate the token")
    end

    it "signs a MessageVerifier payload that verify_token can read" do
      ctx = { payload: { "sub" => "user-1" }, secret: "key" }
      cfg = { "tokenType" => "signed", "payloadVariable" => "payload", "secretSource" => "ctx",
              "secretVariable" => "secret", "resultVar" => "token", "expiresIn" => "1h" }
      expect(execute(cfg, ctx)[:outcome]).to be_truthy
      expect(FlowchartRuntime::Token.verify(ctx[:token], key: "key")).to eq("sub" => "user-1")
    end

    it "issues a numeric OTP of the requested length" do
      ctx = {}
      cfg = { "tokenType" => "numeric_otp", "tokenLength" => 6, "resultVar" => "token" }
      expect(execute(cfg, ctx)[:outcome]).to be_truthy
      expect(ctx[:token]).to match(/\A\d{6}\z/)
    end
  end
end
