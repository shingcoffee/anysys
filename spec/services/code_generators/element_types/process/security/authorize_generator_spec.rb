# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::AuthorizeGenerator do
  let(:context) { {} }
  let(:base) { { "authType" => "role_check", "roleName" => "admin", "userExpression" => "current_user" } }
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
        allowed = FlowchartRuntime::Authorization.allowed?(
          ctx,
          user: ctx[:current_user],
          type: "role_check"
        )
        unless allowed
          return FlowchartRuntime::Step.fail(ctx, :"authorize.denied")
        end
        true
      end
    RUBY
  end

  it "generates a flag assignment without failing" do
    config = described_class.sample_input.merge("onDenied" => "flag", "resultVar" => "authorized")
    expect(generated_step(config)).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:authorized] = FlowchartRuntime::Authorization.allowed?(
          ctx,
          user: ctx[:current_user],
          type: "role_check"
        )
        true
      end
    RUBY
  end

  it "generates an ability check" do
    config = described_class.sample_input.merge(
      "authType" => "ability_check", "abilityAction" => "update", "abilityResource" => "record"
    )
    expect(generated_step(config)).to include('type: "ability_check"')
    expect(generated_step(config)).to include('action: "update"')
    expect(generated_step(config)).to include("resource: ctx[:record]")
  end

  it "generates a multi-role any-of check" do
    config = described_class.sample_input.merge(
      "authType" => "multi_role", "roleList" => %w[admin member]
    )
    expect(generated_step(config)).to include("roles: [:admin, :member]")
    expect(generated_step(config)).not_to include("mode:")
  end

  it "generates a record_owner check" do
    config = described_class.sample_input.merge(
      "authType" => "record_owner", "recordVariable" => "model"
    )
    expect(generated_step(config)).to include('type: "record_owner"')
    expect(generated_step(config)).to include("resource: ctx[:model]")
  end

  it "emits fail_message when a deniedMessage is set" do
    config = described_class.sample_input.merge("deniedMessage" => { "en" => "Staff only", "zh-CN" => "仅限员工" })
    expect(generated_step(config)).to include("FlowchartRuntime::Step.fail_message(ctx,")
    expect(generated_step(config)).to include("Staff only")
  end

  describe "behaviour" do
    it "allows an admin from current_user" do
      user = create(:user, :admin)
      result = execute(base, { current_user: user })
      expect(result[:outcome]).to be(true)
    end

    it "denies when only current_user_role metadata claims admin" do
      ctx = { current_user_role: "admin" }
      result = execute(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.authorize.denied"))
    end

    it "denies a member for an admin role_check" do
      ctx = { current_user: create(:user, :member) }
      result = execute(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.authorize.denied"))
    end

    it "honors multi_role as any listed reserved role" do
      user = create(:user, :admin)
      cfg = { "authType" => "multi_role", "roleList" => %w[admin member], "userExpression" => "current_user" }
      expect(execute(cfg, { current_user: user })[:outcome]).to be(true)
      expect(execute(cfg, { current_user: create(:user, :member) })[:outcome]).to be(true)
    end

    it "allows a member who owns the record and denies another tenant" do
      member = create(:user, :member)
      record = create(:entity_entry, customer: member.customer, user: member)
      foreign = create(:entity_entry)
      cfg = { "authType" => "record_owner", "recordVariable" => "model", "userExpression" => "current_user" }
      expect(execute(cfg, { current_user: member, model: record })[:outcome]).to be(true)
      expect(execute(cfg, { current_user: member, model: foreign })[:outcome]).to be(false)
    end

    it "executes Ability grants and denies another tenant's record" do
      user = create(:user, :admin)
      foreign = create(:user)
      cfg = { "authType" => "ability_check", "abilityAction" => "update", "abilityResource" => "resource",
              "userExpression" => "current_user" }
      expect(execute(cfg, { current_user: user, resource: user })[:outcome]).to be(true)
      expect(execute(cfg, { current_user: user, resource: foreign })[:outcome]).to be(false)
    end

    it "flags denial without failing the step" do
      ctx = { current_user: create(:user, :member) }
      result = execute(base.merge("onDenied" => "flag", "resultVar" => "authorized"), ctx)
      expect(result[:outcome]).to be(true)
      expect(ctx[:authorized]).to be(false)
      expect(ctx[:errors]).to be_nil.or eq([])
    end

    it "uses a custom deniedMessage" do
      ctx = { current_user: create(:user, :member) }
      result = execute(base.merge("deniedMessage" => { "en" => "Staff only" }), ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include("Staff only")
    end

    it "preserves the platform owner's cross-tenant Ability grant" do
      owner = find_or_create_platform_owner
      foreign = create(:user)
      cfg = { "authType" => "ability_check", "abilityAction" => "update", "abilityResource" => "resource",
              "userExpression" => "current_user" }
      expect(execute(cfg, { current_user: owner, resource: foreign })[:outcome]).to be(true)
    end
  end

  describe "#validate_config" do
    it "rejects an invalid authType" do
      expect(errors("authType" => "bogus").map(&:code)).to include(:not_in_list)
    end

    it "requires abilityAction for ability_check" do
      expect(errors("authType" => "ability_check").map(&:field)).to include("abilityAction")
    end

    it "rejects an injected abilityAction" do
      expect(errors("authType" => "ability_check", "abilityAction" => 'read); system("id")',
                    "abilityResource" => "model").map(&:code)).to include(:invalid_ability_action)
    end
  end
end
