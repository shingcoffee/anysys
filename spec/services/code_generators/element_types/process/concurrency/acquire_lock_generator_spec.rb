# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Concurrency::AcquireLockGenerator do
  let(:base) { { "lockKey" => "order_processing" } }
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
          :"acquire_lock.failed",
          FlowchartRuntime::Lock::Error,
          FlowchartRuntime::Template::Error
        ) do
          lock_key = FlowchartRuntime::Template.render("order:{{ model.id }}", ctx)
          lock_token = SecureRandom.hex
          acquired = FlowchartRuntime::Lock.acquire(ctx[:customer_id], lock_key, lock_token, ttl: 30)
          return FlowchartRuntime::Step.fail(ctx, :"acquire_lock.lock_busy") unless acquired
          ctx[:_cache_lock_key] = lock_key
          ctx[:_lock_token] = lock_token
          true
        end
      end
    RUBY
  end

  it "emits skip without failing" do
    expect(generated_step(described_class.sample_input.merge("onConflict" => "skip")))
      .to include("return true unless acquired")
  end

  it "rejects raise as onConflict" do
    expect(errors(base.merge("onConflict" => "raise")).map(&:code)).to include(:not_in_list)
  end

  it "supports a lock key variable and a holder token" do
    code = generated_step(described_class.sample_input.merge("lockKeyVariable" => "job_id", "holderIdentity" => "worker-1"))
    expect(code).to include("ctx[:job_id].to_s")
    expect(code).to include('lock_token = "worker-1"')
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean body for every onConflict" do
    described_class::ON_CONFLICT.each do |mode|
      config = described_class.sample_input.merge("onConflict" => mode)
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[_cache_lock_key _lock_token lockKeyVar tokenVar])
      expect(result.ok?).to be(true), "#{mode}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "stores the key and token when the lock is free" do
      ctx = { customer_id: 1 }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:_cache_lock_key]).to eq("order_processing")
      expect(ctx[:_lock_token]).to be_present
    end

    it "fails with a translated lock_busy message and does not wait" do
      expect(FlowchartRuntime::Lock).not_to receive(:sleep)
      FlowchartRuntime::Lock.acquire(1, "order_processing", "other", ttl: 30)
      ctx = { customer_id: 1 }
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.acquire_lock.lock_busy"))
    end

    it "isolates identical lock keys by tenant" do
      expect(execute(base, { customer_id: 1 })[:outcome]).to be_truthy
      expect(execute(base, { customer_id: 2 })[:outcome]).to be_truthy
    end
  end

  describe "#validate_config" do
    it "requires a lock key or lock key variable" do
      expect(errors({}).map(&:field)).to include("lockKey")
    end

    it "rejects wait as onConflict" do
      expect(errors(base.merge("onConflict" => "wait")).map(&:code)).to include(:not_in_list)
    end

    it "rejects an injected holder expression" do
      expect(errors(base.merge("holderIdentity" => 'ctx[system("id")]')).map(&:code)).to include(:invalid_holder)
    end
  end
end
