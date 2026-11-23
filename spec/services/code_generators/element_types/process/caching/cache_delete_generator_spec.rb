# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Caching::CacheDeleteGenerator do
  let(:context) { {} }
  let(:base) { { "cacheKey" => "product_123", "scope" => "key" } }
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
          :"cache_delete.failed",
          FlowchartRuntime::CacheKey::Error,
          FlowchartRuntime::CacheScope::Error,
          FlowchartRuntime::CacheTags::Error,
          FlowchartRuntime::Template::Error
        ) do
          Rails.cache.delete(FlowchartRuntime::CacheKey.scoped(
            ctx[:customer_id],
            FlowchartRuntime::Template.render("order_summary:{{ model.id }}", ctx)
          ))
          true
        end
      end
    RUBY
  end

  it "emits a distinct helper for each scope" do
    expect(generated_step({ "scope" => "key", "cacheKey" => "k" })).to include("Rails.cache.delete(FlowchartRuntime::CacheKey.scoped")
    expect(generated_step({ "scope" => "pattern", "cacheKey" => "k_*" })).to include("CacheScope.delete_matched")
    expect(generated_step({ "scope" => "pattern", "cacheKey" => "k_*" })).to include("max_keys: 10000")
    expect(generated_step({ "scope" => "pattern", "cacheKey" => "k_*", "confirmPattern" => false })).not_to include("max_keys")
    expect(generated_step({ "scope" => "namespace", "cacheKey" => "tenant_42" })).to include('"tenant_42" + "*"')
    expect(generated_step({ "scope" => "all" })).to include("CacheScope.clear(ctx[:customer_id])")
    expect(generated_step({ "scope" => "tagged", "tags" => ["user"] })).to include('CacheTags.invalidate(ctx[:customer_id], "user")')
  end

  it "never calls Rails.cache.delete_matched" do
    configs = [
      { "scope" => "key", "cacheKey" => "k" },
      { "scope" => "pattern", "cacheKey" => "k_*" },
      { "scope" => "namespace", "cacheKey" => "k" },
      { "scope" => "all" },
      { "scope" => "tagged", "tags" => ["user"] }
    ]
    configs.each do |config|
      expect(generated_step(config)).not_to include("Rails.cache.delete_matched")
    end
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean body for every scope" do
    described_class::SCOPES.each do |scope|
      config = { "scope" => scope, "cacheKey" => "user_data", "tags" => ["user"], "confirmPattern" => true }
      result = CodeGenerators::BodyLint.check(body(config), outputs: [])
      expect(result.ok?).to be(true), "#{scope}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "deletes only the calling tenant's key" do
      cache.write(FlowchartRuntime::CacheKey.scoped(1, "product_123"), "mine")
      cache.write(FlowchartRuntime::CacheKey.scoped(2, "product_123"), "theirs")
      expect(execute(base, { customer_id: 1 })[:outcome]).to be_truthy
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(1, "product_123"))).to be_nil
      expect(cache.read(FlowchartRuntime::CacheKey.scoped(2, "product_123"))).to eq("theirs")
    end
  end

  describe "#validate_config" do
    it "requires cacheKey for key scope" do
      expect(errors({}).map(&:field)).to include("cacheKey")
    end

    it "requires tags for tagged scope" do
      expect(errors("scope" => "tagged").map(&:field)).to include("tags")
    end

    it "does not require cacheKey for all scope" do
      expect(errors("scope" => "all").map(&:field)).not_to include("cacheKey")
    end
  end
end
