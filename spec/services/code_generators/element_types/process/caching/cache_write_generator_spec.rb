# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator do
  let(:context) { {} }
  let(:base) { { "cacheKey" => "user_42", "sourceVariable" => "user", "ttl" => 600 } }
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

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"cache_write.failed",
          FlowchartRuntime::CacheKey::Error,
          FlowchartRuntime::CacheTags::Error,
          FlowchartRuntime::Template::Error
        ) do
          cache_key = FlowchartRuntime::CacheKey.scoped(
            ctx[:customer_id],
            FlowchartRuntime::Template.render("order_summary:{{ model.id }}", ctx)
          )
          Rails.cache.write(cache_key, ctx[:data])
          true
        end
      end
    RUBY
  end

  it "emits write and write_if_absent variants" do
    expect(generated_step(described_class.sample_input.merge("action" => "write"))).not_to include("unless_exist")
    expect(generated_step(described_class.sample_input.merge("action" => "write_if_absent", "ttl" => 600)))
      .to include("unless_exist: true")
  end

  it "emits raceConditionTtl as race_condition_ttl" do
    code = generated_step(described_class.sample_input.merge("raceConditionTtl" => 5))
    expect(code).to include("race_condition_ttl: 5")
  end

  it "does not emit compress or raw knobs" do
    code = generated_step(described_class.sample_input.merge("compress" => false, "raw" => true))
    expect(code).not_to include("compress:")
    expect(code).not_to include("raw:")
  end

  it "tags written keys" do
    code = generated_step(described_class.sample_input.merge("tags" => ["env", "role"], "ttl" => 600))
    expect(code).to include('FlowchartRuntime::CacheTags.tag(')
    expect(code).to include('["env", "role"]')
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean body for every action" do
    described_class::ACTIONS.each do |action|
      config = described_class.sample_input.merge("action" => action)
      result = CodeGenerators::BodyLint.check(body(config), outputs: [])
      expect(result.ok?).to be(true), "#{action}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "writes under the tenant-scoped key" do
      ctx = { customer_id: 1, user: { id: 9 } }
      expect(execute(base, ctx)[:outcome]).to be_truthy
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(1, "user_42"))).to eq({ id: 9 })
    end

    it "never writes tenant A's value onto tenant B's key" do
      execute(base, { customer_id: 1, user: "a" })
      execute(base, { customer_id: 2, user: "b" })
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(1, "user_42"))).to eq("a")
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(2, "user_42"))).to eq("b")
    end

    it "skips an existing key on write_if_absent" do
      key = FlowchartRuntime::CacheKey.scoped(1, "user_42")
      cache.write(key, "kept")
      execute(base.merge("action" => "write_if_absent"), { customer_id: 1, user: "new" })
      expect(cache.read(key)).to eq("kept")
    end
  end

  describe "#validate_config" do
    it "requires cacheKey" do
      expect(errors({}).map(&:field)).to include("cacheKey")
    end

    it "rejects delete as an action" do
      expect(errors("cacheKey" => "k", "action" => "delete").map(&:code)).to include(:not_in_list)
    end
  end
end
