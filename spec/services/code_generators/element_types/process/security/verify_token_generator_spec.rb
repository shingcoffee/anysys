# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::VerifyTokenGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "auth_token", "secretSource" => "ctx", "secretVariable" => "jwt_secret",
      "algorithm" => "HS256", "resultVar" => "claims" }
  end
  let(:element) { { "config" => base } }
  let(:secret) { "security-regression-signing-secret" }

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
        FlowchartRuntime::Step.attempt(ctx, :"verify_token.failed", FlowchartRuntime::Jwt::Error) do
          ctx[:claims] = FlowchartRuntime::Jwt.verify(
            ctx[:token],
            Rails.application.credentials.dig(:secret),
            algorithms: ["HS256"]
          )
          true
        end
      end
    RUBY
  end

  it "generates verify_or_nil when onInvalid is flag" do
    expect(generated_step(described_class.sample_input.merge("onInvalid" => "flag"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(ctx, :"verify_token.failed", FlowchartRuntime::Jwt::Error) do
          claims = FlowchartRuntime::Jwt.verify_or_nil(
            ctx[:token],
            Rails.application.credentials.dig(:secret),
            algorithms: ["HS256"]
          )
          ctx[:claims] = claims
          ctx[:token_valid] = !claims.nil?
          true
        end
      end
    RUBY
  end

  it "generates Token.verify for signed tokens" do
    config = described_class.sample_input.merge("tokenType" => "signed", "secretSource" => "ctx",
                                               "secretVariable" => "jwt_secret")
    expect(generated_step(config)).to include("FlowchartRuntime::Token.verify(")
    expect(generated_step(config)).to include("key: ctx[:jwt_secret]")
  end

  describe "behaviour" do
    it "accepts valid issuer, audience and nested required claims" do
      cfg = base.merge("verifyIssuer" => "issuer", "verifyAudience" => "api",
                       "requiredClaims" => [{ "key" => "user.role", "value" => "admin" }])
      payload = { "iss" => "issuer", "aud" => ["web", "api"], "user" => { "role" => "admin" },
                  "exp" => 1.hour.from_now.to_i }
      ctx = { auth_token: FlowchartRuntime::Jwt.encode(payload, secret), jwt_secret: secret }
      expect(execute(cfg, ctx)[:outcome]).to be_truthy
      expect(ctx[:claims]).to include("iss" => "issuer", "user" => { "role" => "admin" })
    end

    it "flags an invalid token without failing the step" do
      ctx = { auth_token: "not-a-jwt", jwt_secret: secret, errors: [] }
      result = execute(base.merge("onInvalid" => "flag", "validVar" => "token_valid"), ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:token_valid]).to be(false)
      expect(ctx[:claims]).to be_nil
      expect(ctx[:errors]).to eq([])
    end

    it "rejects an expired token and records a translated failure" do
      ctx = { auth_token: FlowchartRuntime::Jwt.encode({ "exp" => 1 }, secret), jwt_secret: secret,
              claims: { "role" => "admin" } }
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not verify the token")
    end

    it "preserves false as a valid required claim value" do
      cfg = base.merge("requiredClaims" => [{ "key" => "user.enabled", "value" => false }])
      ctx = { auth_token: FlowchartRuntime::Jwt.encode({ "user" => { "enabled" => false } }, secret),
              jwt_secret: secret }
      expect(execute(cfg, ctx)[:outcome]).to be_truthy
    end

    it "honors the expiration leeway boundary" do
      travel_to(Time.utc(2026, 1, 1)) do
        ctx = { auth_token: FlowchartRuntime::Jwt.encode({ "exp" => Time.current.to_i - 5 }, secret),
                jwt_secret: secret }
        expect(execute(base.merge("leewaySeconds" => 10), ctx)[:outcome]).to be_truthy
        expect(execute(base.merge("leewaySeconds" => 5), ctx)[:outcome]).to eq(false)
      end
    end

    it "verifies a signed payload from generate_token" do
      token = FlowchartRuntime::Token.sign({ "sub" => "user-1" }, key: secret)
      ctx = { auth_token: token, jwt_secret: secret }
      result = execute(base.merge("tokenType" => "signed"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:claims]).to eq("sub" => "user-1")
    end
  end
end
