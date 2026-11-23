# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Workflow::SelectAssigneeGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
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

  let(:agents) do
    [
      { "id" => "ann", "weight" => 1, "open_items" => 5, "available" => true },
      { "id" => "bo", "weight" => 3, "open_items" => 1, "available" => true },
      { "id" => "cy", "weight" => 1, "open_items" => 9, "available" => false }
    ]
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"select_assignee.failed",
          FlowchartRuntime::Assignment::Error
        ) do
          ctx[:assignee] = FlowchartRuntime::Assignment.pick(ctx, ctx[:agents], strategy: "round_robin")
          next FlowchartRuntime::Step.fail(ctx, :"select_assignee.no_candidates") unless ctx[:assignee]
          true
        end
      end
    RUBY
  end

  it "omits the empty-pool guard when onEmpty is nil" do
    code = generated_step(described_class.sample_input.merge("strategy" => "first", "onEmpty" => "nil"))
    expect(code).to include('strategy: "first"')
    expect(code).not_to include("select_assignee.no_candidates")
  end

  it "requires sourceVariable unless candidates come from a role" do
    expect(errors({}).map(&:field)).to include("sourceVariable")
    expect(errors("candidateSource" => "role").map(&:field)).not_to include("sourceVariable")
  end

  it "picks from this tenant's users of a role" do
    expect(generated_step(described_class.sample_input.merge("candidateSource" => "role", "role" => "member")))
      .to include('FlowchartRuntime::Assignment.users_of_role(ctx, "member")')
  end

  described_class::STRATEGIES.each do |strategy|
    it "emits a BodyLint-clean body for strategy #{strategy}" do
      config = described_class.sample_input.merge("strategy" => strategy)
      src = generate(config)
      result = CodeGenerators::BodyLint.check(src, outputs: %w[assignee])
      expect(result.ok?).to be(true), "#{result.violations.inspect}\n#{src}"
      expect(src).to include("FlowchartRuntime::Assignment.pick")
    end
  end

  it "emits a distinct body for every strategy, returns, and onEmpty" do
    strategies = described_class::STRATEGIES.map { |value| generate(described_class.sample_input.merge("strategy" => value)) }
    expect(strategies.uniq.size).to eq(described_class::STRATEGIES.size)
    returns = described_class::RETURNS.map { |value| generate(described_class.sample_input.merge("returns" => value)) }
    expect(returns.uniq.size).to eq(described_class::RETURNS.size)
    empties = described_class::ON_EMPTY.map { |value| generate(described_class.sample_input.merge("onEmpty" => value)) }
    expect(empties.uniq.size).to eq(described_class::ON_EMPTY.size)
  end

  it "does not emit poolKey while strategy is not round_robin" do
    base = generate(described_class.sample_input.merge("strategy" => "first"))
    leaked = generate(described_class.sample_input.merge("strategy" => "first", "poolKey" => "other-desk"))
    expect(leaked).to eq(base)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }

    def ctx_for(customer, extras = {})
      { customer_id: customer.id, agents: agents, errors: [] }.merge(extras)
    end

    it "picks the first eligible candidate through the generated body" do
      ctx = ctx_for(customer)
      expect(run_body(described_class.sample_input.merge("strategy" => "first"), ctx)).to be(true)
      expect(ctx[:assignee]["id"]).to eq("ann")
    end

    described_class::STRATEGIES.each do |strategy|
      it "executes strategy #{strategy} against a real ctx" do
        ctx = ctx_for(customer)
        config = described_class.sample_input.merge("strategy" => strategy)
        allow(SecureRandom).to receive(:random_number).and_return(strategy == "random" ? 1 : 0.0)
        result = execute(config, ctx)
        expect(result[:validation_errors]).to eq([])
        expect(result[:outcome]).to be(true)
        expect(ctx[:assignee]).to be_present
        case strategy
        when "first", "round_robin" then expect(ctx[:assignee]["id"]).to eq("ann")
        when "least_loaded" then expect(ctx[:assignee]["id"]).to eq("bo")
        when "random" then expect(ctx[:assignee]["id"]).to eq("bo")
        when "weighted" then expect(ctx[:assignee]["id"]).to eq("ann")
        end
      end
    end

    described_class::RETURNS.each do |mode|
      it "returns #{mode}" do
        ctx = ctx_for(customer)
        execute(described_class.sample_input.merge("strategy" => "first", "returns" => mode), ctx)
        if mode == "id"
          expect(ctx[:assignee]).to eq("ann")
        else
          expect(ctx[:assignee]["id"]).to eq("ann")
        end
      end
    end

    described_class::ON_EMPTY.each do |mode|
      it "handles onEmpty #{mode} when the pool is empty" do
        ctx = ctx_for(customer, agents: [])
        result = execute(described_class.sample_input.merge("strategy" => "first", "onEmpty" => mode), ctx)
        if mode == "fail"
          expect(result[:outcome]).to eq(false)
          expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.select_assignee.no_candidates")])
        else
          expect(result[:outcome]).to be(true)
          expect(ctx[:assignee]).to be_nil
        end
      end
    end

    it "honors availabilityField and excludeVariable" do
      ctx = ctx_for(customer, skip: "ann")
      config = described_class.sample_input.merge(
        "strategy" => "first",
        "availabilityField" => "available",
        "excludeVariable" => "skip"
      )
      execute(config, ctx)
      expect(ctx[:assignee]["id"]).to eq("bo")
    end

    it "keeps round-robin rotation independent across tenants" do
      config = described_class.sample_input.merge("strategy" => "round_robin", "poolKey" => "desk")
      execute(config, ctx_for(customer))
      other_ctx = ctx_for(other)
      execute(config, other_ctx)
      expect(other_ctx[:assignee]["id"]).to eq("ann")
    end

    it "picks an admin of this tenant and ignores another tenant's admins" do
      create(:user, :admin, customer: customer)
      create(:user, :member, customer: customer)
      foreign = create(:user, :admin, customer: other)
      ctx = { customer_id: customer.id, errors: [] }
      result = execute(
        described_class.sample_input.merge("candidateSource" => "role", "role" => "admin", "strategy" => "first"),
        ctx
      )
      expect(result[:outcome]).to be_truthy
      expect(ctx[:assignee]).to be_a(Authentication::User)
      expect(ctx[:assignee].customer_id).to eq(customer.id)
      expect(ctx[:assignee]).to be_admin
      expect(ctx[:assignee]).not_to eq(foreign)
    end
  end
end
