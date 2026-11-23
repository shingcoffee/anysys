# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Resilience::RateLimiterGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"rate_limiter.failed",
          FlowchartRuntime::RateLimiter::Error,
          FlowchartRuntime::CacheKey::Error
        ) do
          decision = FlowchartRuntime::RateLimiter.check(ctx, "api_calls", capacity: 100, window: 60)
          ctx[:throttle_state] = decision[:allowed]
          ctx[:retry_after_seconds] = decision[:retry_after]
          return FlowchartRuntime::Step.fail(ctx, :rate_limited) unless decision[:allowed]
          true
        end
      end
    RUBY
  end

  it "emits skip without failing" do
    code = generated_step(described_class.sample_input.merge("onExceed" => "skip"))
    expect(code).not_to include("rate_limited")
    expect(code).to include("true")
  end

  it "emits custom scope_value and cost when they are not defaults" do
    custom = generated_step(described_class.sample_input.merge("scope" => "custom", "scopeVariable" => "order_id"))
    expect(custom).to include('scope: "custom"')
    expect(custom).to include("scope_value: ctx[:order_id]")
    expect(generated_step(described_class.sample_input.merge("cost" => 3))).to include("cost: 3")
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "emits a BodyLint-clean body for each onExceed variant" do
    %w[fail skip].each do |mode|
      code = generate(described_class.sample_input.merge("onExceed" => mode))
      result = CodeGenerators::BodyLint.check(code, outputs: %w[throttle_state retry_after_seconds])
      expect(result.ok?).to be(true), "#{mode}: #{result.violations.inspect}\n#{code}"
      expect(code).not_to include("sleep")
    end
  end

  describe "behaviour" do
    before { ::Authentication::Throttle.store = ActiveSupport::Cache::MemoryStore.new }
    after { ::Authentication::Throttle.reset_store! }

    it "admits up to capacity then fails with a translated rate_limited message" do
      config = described_class.sample_input.merge("limiterName" => "signup", "capacity" => 1, "window" => 60)
      first = { customer_id: 41, errors: [] }
      second = { customer_id: 41, errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: first)[:outcome]).to be(true)
      denied = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: second)
      expect(denied[:outcome]).to be(false)
      expect(second[:errors]).to eq([I18n.t("flowchart_runtime.errors.rate_limited")])
      expect(second[:retry_after_seconds]).to be > 0
    end

    it "never waits when onExceed is fail" do
      expect(Kernel).not_to receive(:sleep)
      ctx = { customer_id: 41, errors: [] }
      config = described_class.sample_input.merge("capacity" => 1, "onExceed" => "fail")
      CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
      CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
    end

    it "does not share user-scoped buckets across users of the same tenant" do
      config = described_class.sample_input.merge(
        "limiterName" => "signup", "capacity" => 1, "window" => 60, "scope" => "user"
      )
      alice = { customer_id: 41, current_user_id: 7, errors: [] }
      bob = { customer_id: 41, current_user_id: 8, errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: alice)[:outcome]).to be(true)
      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: bob)[:outcome]).to be(true)
    end

    it "consumes cost slots in one run" do
      config = described_class.sample_input.merge(
        "limiterName" => "weighted", "capacity" => 3, "window" => 60, "cost" => 3
      )
      first = { customer_id: 41, errors: [] }
      second = { customer_id: 41, errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: first)[:outcome]).to be(true)
      denied = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: second)
      expect(denied[:outcome]).to be(false)
    end
  end
end
