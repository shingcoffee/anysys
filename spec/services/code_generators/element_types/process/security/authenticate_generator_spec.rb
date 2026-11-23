# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::AuthenticateGenerator do
  include FlowchartAuthenticationHelpers

  let(:context) { {} }
  let(:base) do
    { "authMethod" => "password", "sourceVariable" => "credentials", "userVariable" => "user",
      "resultVar" => "authenticated_user" }
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
        authenticated = FlowchartRuntime::Authentication.password(
          user: ctx[:user],
          password: ctx[:credentials],
          customer_id: ctx[:customer_id]
        )
        ctx[:authenticated_user] = authenticated
        unless authenticated
          return FlowchartRuntime::Step.fail(ctx, :"authenticate.failed", field: :sourceVariable)
        end
        true
      end
    RUBY
  end

  it "generates a session check" do
    expect(generated_step(described_class.sample_input.merge("authMethod" => "session"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        authenticated = FlowchartRuntime::Authentication.session(
          context: ctx[:authentication],
          customer_id: ctx[:customer_id]
        )
        ctx[:authenticated_user] = authenticated
        unless authenticated
          return FlowchartRuntime::Step.fail(ctx, :"authenticate.failed")
        end
        true
      end
    RUBY
  end

  it "generates a bearer token comparison" do
    config = described_class.sample_input.merge(
      "authMethod" => "token", "expectedKeyVariable" => "stored_key", "tokenType" => "bearer"
    )
    expect(generated_step(config)).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        authenticated = FlowchartRuntime::Authentication.token(
          raw: ctx[:credentials],
          expected: ctx[:stored_key]
        )
        ctx[:authenticated_user] = authenticated
        unless authenticated
          return FlowchartRuntime::Step.fail(ctx, :"authenticate.failed", field: :expectedKeyVariable)
        end
        true
      end
    RUBY
  end

  it "generates an API key comparison from params" do
    config = described_class.sample_input.merge(
      "authMethod" => "api_key", "expectedKeyVariable" => "stored_key", "credentialSource" => "params"
    )
    expect(generated_step(config)).to include("FlowchartRuntime::Step.dig(ctx[:params], :credentials)")
    expect(generated_step(config)).to include("FlowchartRuntime::Authentication.api_key(")
  end

  it "flags a failed password without aborting the step" do
    expect(generated_step(described_class.sample_input.merge("onFailure" => "flag"))).not_to include("Step.fail")
  end

  it "does not emit jwt or oauth branches" do
    expect(described_class::AUTH_METHODS).not_to include("jwt", "oauth")
    expect(errors("authMethod" => "jwt").map(&:code)).to include(:not_in_list)
  end

  describe "behaviour" do
    let(:user) { create(:user) }

    it "authenticates the application's Devise user with the correct password" do
      ctx = { user: user, credentials: "password123", customer_id: user.customer_id }
      result = execute(base, ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:authenticated_user]).to eq(user)
    end

    it "rejects a wrong password and records a translated failure" do
      ctx = { user: user, credentials: "wrong", customer_id: user.customer_id, authenticated_user: user }
      result = execute(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:authenticated_user]).to be_nil
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.authenticate.failed"))
    end

    it "flags a failed password without aborting the step" do
      ctx = { user: user, credentials: "wrong", customer_id: user.customer_id, errors: [] }
      result = execute(base.merge("onFailure" => "flag"), ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:authenticated_user]).to be_nil
      expect(ctx[:errors]).to eq([])
    end

    it "does not authenticate a password user from a different tenant" do
      ctx = { user: user, credentials: "password123", customer_id: create(:customer).id }
      expect(execute(base, ctx)[:outcome]).to be(false)
    end

    it "authenticates a session via the request facade" do
      cfg = { "authMethod" => "session", "resultVar" => "authenticated_user" }
      ctx = { authentication: FlowchartRuntime::Authentication.from_request(warden_round_trip(user)),
              customer_id: user.customer_id }
      expect(execute(cfg, ctx)[:outcome]).to be(true)
      expect(ctx[:authenticated_user]).to eq(user)
    end

    it "compares a bearer token in constant time" do
      cfg = base.merge("authMethod" => "token", "expectedKeyVariable" => "stored", "tokenType" => "bearer")
      ctx = { credentials: "Bearer secret", stored: "secret" }
      expect(execute(cfg, ctx)[:outcome]).to be(true)
      expect(ctx[:authenticated_user]).to eq("secret")
      ctx[:credentials] = "Bearer wrong"
      expect(execute(cfg, ctx)[:outcome]).to be(false)
      expect(ctx[:authenticated_user]).to be_nil
    end

    it "compares an API key from params" do
      cfg = base.merge("authMethod" => "api_key", "credentialSource" => "params",
                       "expectedKeyVariable" => "stored")
      ctx = { params: { "credentials" => "secret" }, stored: "secret" }
      expect(execute(cfg, ctx)[:outcome]).to be(true)
      expect(ctx[:authenticated_user]).to be(true)
    end
  end
end
