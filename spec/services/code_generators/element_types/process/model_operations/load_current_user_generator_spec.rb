# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::LoadCurrentUserGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def run_body(config, ctx)
    body = generate(config)
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        user = FlowchartRuntime::CurrentUser.load(ctx)
        ctx[:current_user] = user
        return FlowchartRuntime::Step.fail(ctx, :"load_current_user.not_signed_in") unless user
        true
      end
    RUBY
  end

  it "emits a BodyLint-clean required load and an optional variant" do
    required = generate("required" => true, "resultVar" => "current_user")
    expect(required).to include("ctx[:current_user] = user")
    expect(required).to include('return FlowchartRuntime::Step.fail(ctx, :"load_current_user.not_signed_in") unless user')
    expect(CodeGenerators::BodyLint.check(required, outputs: %w[current_user]).ok?).to be(true)

    optional = generate("required" => false, "resultVar" => "viewer")
    expect(optional).to include("ctx[:viewer] = FlowchartRuntime::CurrentUser.load(ctx)")
    expect(optional).to include("true")
    expect(optional).not_to include("not_signed_in")
    expect(CodeGenerators::BodyLint.check(optional, outputs: %w[viewer]).ok?).to be(true)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:user) { create(:user, :member, customer: customer, first_name: "Lin", last_name: "Yuan") }
    let(:foreign) { create(:user, :admin, customer: other) }

    it "loads the tenant user and fails with a translated message when required and missing" do
      ctx = { customer_id: customer.id, current_user_id: user.id, errors: [] }
      expect(run_body({ "required" => true }, ctx)).to be(true)
      expect(ctx[:current_user]).to include("id" => user.id, "email" => user.email, "role" => "member")
      expect(ctx[:current_user]).to be_frozen

      missing = { customer_id: customer.id, current_user_id: foreign.id, errors: [] }
      expect(run_body({ "required" => true }, missing)).to be(false)
      expect(missing[:current_user]).to be_nil
      expect(missing[:errors]).to eq([I18n.t("flowchart_runtime.errors.load_current_user.not_signed_in")])

      optional = { customer_id: customer.id, current_user_id: foreign.id, errors: [] }
      expect(run_body({ "required" => false }, optional)).to be(true)
      expect(optional[:current_user]).to be_nil
      expect(optional[:errors]).to eq([])
    end
  end
end
