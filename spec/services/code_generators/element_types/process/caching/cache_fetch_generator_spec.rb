# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Caching::CacheFetchGenerator do
  let(:context) { {} }
  let(:base) { { "cacheKey" => "expensive_query", "ttl" => 300, "fallbackExpression" => "user_id", "resultVar" => "count" } }
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
          :"cache_fetch.failed",
          FlowchartRuntime::CacheKey::Error,
          FlowchartRuntime::Template::Error
        ) do
          cache_key = FlowchartRuntime::CacheKey.scoped(
            ctx[:customer_id],
            FlowchartRuntime::Template.render("order_summary:{{ model.id }}", ctx)
          )
          ctx[:cached] = Rails.cache.fetch(cache_key, skip_nil: true) { ctx[:order_total] }
          true
        end
      end
    RUBY
  end

  it "emits force, ttl, race_condition_ttl, namespace, and version when set" do
    config = described_class.sample_input.merge(
      "ttl" => 300, "forceRefresh" => true, "skipNilCache" => false,
      "raceConditionTtl" => 10, "versionKey" => "v2", "namespace" => "reports"
    )
    code = generated_step(config)
    expect(code).to include("expires_in: 300")
    expect(code).to include("force: true")
    expect(code).to include("race_condition_ttl: 10")
    expect(code).to include('version: "v2"')
    expect(code).to include('namespace: "reports"')
    expect(code).not_to include("skip_nil:")
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean sample body" do
    sample = described_class.sample_input
    result = CodeGenerators::BodyLint.check(body(sample), outputs: [sample["resultVar"] || "cached"])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "returns a hit without reading the fallback" do
      cache.write(FlowchartRuntime::CacheKey.scoped(1, "expensive_query"), 99)
      ctx = { customer_id: 1, user_id: 7 }
      expect(execute(base, ctx)[:outcome]).to be_truthy
      expect(ctx[:count]).to eq(99)
    end

    it "computes the fallback on miss and stores it under the tenant key" do
      ctx = { customer_id: 1, user_id: 7 }
      execute(base, ctx)
      expect(ctx[:count]).to eq(7)
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(1, "expensive_query"))).to eq(7)
    end

    it "never lets tenant A fetch tenant B's entry" do
      cache.write(FlowchartRuntime::CacheKey.scoped(2, "expensive_query"), "secret-b")
      ctx = { customer_id: 1, user_id: "from-a" }
      execute(base, ctx)
      expect(ctx[:count]).to eq("from-a")
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(2, "expensive_query"))).to eq("secret-b")
    end
  end

  describe "#validate_config" do
    it "requires cacheKey and fallbackExpression" do
      expect(errors({}).map(&:field)).to include("cacheKey", "fallbackExpression")
    end

    it "rejects a raw Ruby fallback" do
      expect(errors("cacheKey" => "k", "fallbackExpression" => "User.destroy_all").map(&:code))
        .to include(:invalid_identifier)
    end
  end
end
