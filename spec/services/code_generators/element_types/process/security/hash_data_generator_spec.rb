# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::HashDataGenerator do
  let(:context) { {} }
  let(:base) { { "sourceVariable" => "password", "resultVar" => "hashed", "algorithm" => "sha256" } }
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
        FlowchartRuntime::Step.attempt(
          ctx,
          :"hash_data.failed",
          FlowchartRuntime::Crypto::Error,
          FlowchartRuntime::PasswordHash::Error
        ) do
          ctx[:hashed] = FlowchartRuntime::Crypto.digest("sha256", ctx[:password])
          true
        end
      end
    RUBY
  end

  it "generates bcrypt without the default cost" do
    expect(generated_step(described_class.sample_input.merge("algorithm" => "bcrypt"))).to include(
      'FlowchartRuntime::PasswordHash.create("bcrypt", ctx[:password].to_s)'
    )
    expect(generated_step(described_class.sample_input.merge("algorithm" => "bcrypt", "cost" => 10)))
      .to include("cost: 10")
  end

  it "emits argon2 time and memory costs when they differ from the defaults" do
    code = body(base.merge("algorithm" => "argon2", "timeCost" => 3, "memoryCost" => 12))
    expect(code).to include("t_cost: 3")
    expect(code).to include("m_cost: 12")
  end

  describe "behaviour" do
    it "writes a sha256 hex digest" do
      ctx = { password: "secret" }
      expect(execute(base, ctx)[:outcome]).to be_truthy
      expect(ctx[:hashed]).to eq(Digest::SHA256.hexdigest("secret"))
    end

    it "prepends salt and appends pepper" do
      ctx = { password: "secret", salt: "s", pepper: "p" }
      execute(base.merge("salt" => "salt", "pepper" => "pepper"), ctx)
      expect(ctx[:hashed]).to eq(Digest::SHA256.hexdigest("ssecretp"))
    end

    it "creates a bcrypt hash that verifies" do
      ctx = { password: "secret" }
      expect(execute(base.merge("algorithm" => "bcrypt"), ctx)[:outcome]).to be_truthy
      expect(BCrypt::Password.new(ctx[:hashed])).to eq("secret")
    end

    it "rejects md5 as a hashing algorithm" do
      expect(errors(base.merge("algorithm" => "md5")).map(&:code)).to include(:not_in_list)
    end
  end
end
