# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Concurrency::ReleaseLockGenerator do
  let(:base) { { "lockKey" => "inventory_lock" } }
  let(:element) { { "config" => base } }
  let(:context) { {} }

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

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"release_lock.failed",
          FlowchartRuntime::Lock::Error,
          FlowchartRuntime::Template::Error
        ) do
          lock_key = FlowchartRuntime::Template.render("order:{{ model.id }}", ctx)
          holder = ctx[:_lock_token]
          FlowchartRuntime::Lock.release(ctx[:customer_id], lock_key, holder)
          true
        end
      end
    RUBY
  end

  it "fails when onMissing is fail" do
    expect(generated_step(described_class.sample_input.merge("onMissing" => "fail")))
      .to include(':"release_lock.not_held"')
  end

  it "logs when onMissing is log" do
    expect(generated_step(described_class.sample_input.merge("onMissing" => "log")))
      .to include("Rails.logger.warn")
  end

  it "pairs with acquire_lock defaults when lockKey is blank" do
    code = generated_step({})
    expect(code).to include("lock_key = ctx[:_cache_lock_key]")
    expect(code).to include("holder = ctx[:_lock_token]")
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean body for every onMissing" do
    described_class::ON_MISSING.each do |mode|
      result = CodeGenerators::BodyLint.check(body(base.merge("onMissing" => mode)), outputs: [])
      expect(result.ok?).to be(true), "#{mode}: #{result.violations.inspect}"
    end
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "releases a lock acquired for the same tenant" do
      acquire = CodeGenerators::ElementTypes::Process::Concurrency::AcquireLockGenerator
      ctx = { customer_id: 81721200 }
      expect(CodeGenerators::TestRunner.execute(acquire, config: base, ctx: ctx)[:outcome]).to be_truthy
      expect(execute(base, ctx)[:outcome]).to be_truthy
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(81721200, "lock", "inventory_lock"))).to be_nil
    end

    it "releases using the token stored by acquire_lock when keys are blank" do
      acquire = CodeGenerators::ElementTypes::Process::Concurrency::AcquireLockGenerator
      ctx = { customer_id: 1 }
      expect(CodeGenerators::TestRunner.execute(acquire, config: base, ctx: ctx)[:outcome]).to be_truthy
      expect(execute({}, ctx)[:outcome]).to be_truthy
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(1, "lock", "inventory_lock"))).to be_nil
    end

    it "fails with a translated message when the token does not match" do
      FlowchartRuntime::Lock.acquire(1, "inventory_lock", "other", ttl: 30)
      ctx = { customer_id: 1, _lock_token: "mine" }
      result = execute(base.merge("onMissing" => "fail"), ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.release_lock.not_held"))
    end
  end

  describe "#validate_config" do
    it "accepts a blank lock key so acquire_lock defaults can pair" do
      expect(errors({}).map(&:field)).not_to include("lockKey")
    end
  end
end
