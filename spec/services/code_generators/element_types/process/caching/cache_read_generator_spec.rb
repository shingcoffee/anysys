# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Caching::CacheReadGenerator do
  let(:context) { {} }
  let(:base) { { "cacheKey" => "user_42", "resultVar" => "data" } }
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
          :"cache_read.failed",
          FlowchartRuntime::CacheKey::Error,
          FlowchartRuntime::Template::Error
        ) do
          cache_key = FlowchartRuntime::CacheKey.scoped(
            ctx[:customer_id],
            FlowchartRuntime::Template.render("order_summary:{{ model.id }}", ctx)
          )
          ctx[:cached] = Rails.cache.read(cache_key)
          true
        end
      end
    RUBY
  end

  it "assigns the default expression on miss" do
    expect(generated_step(described_class.sample_input.merge("onMiss" => "default", "defaultValue" => "42")))
      .to include("ctx[:cached] ||= 42")
  end

  it "emits namespace and version when set" do
    code = generated_step(described_class.sample_input.merge("namespace" => "tenant_7", "versionCheck" => "v2"))
    expect(code).to include('namespace: "tenant_7"')
    expect(code).to include('ctx[:cached] = Rails.cache.read(cache_key, version: "v2")')
  end

  it "ignores a leftover decompressOnRead key" do
    expect(generated_step(described_class.sample_input.merge("decompressOnRead" => true))).to eq(generated_step)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "lints a BodyLint-clean body for every onMiss" do
    described_class::ON_MISS.each do |mode|
      config = described_class.sample_input.merge("onMiss" => mode, "defaultValue" => "{}")
      result = CodeGenerators::BodyLint.check(body(config), outputs: [described_class.sample_input["resultVar"] || "cached"])
      expect(result.ok?).to be(true), "#{mode}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "reads a tenant-scoped hit" do
      cache.write(FlowchartRuntime::CacheKey.scoped(1, "user_42"), { id: 7 })
      ctx = { customer_id: 1 }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:data]).to eq({ id: 7 })
    end

    it "renders a Liquid cacheKey from the record id" do
      cache.write(FlowchartRuntime::CacheKey.scoped(1, "order_summary:9"), { total: 4 })
      ctx = { customer_id: 1, model: { "id" => 9 } }
      result = execute(base.merge("cacheKey" => "order_summary:{{ model.id }}"), ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:data]).to eq({ total: 4 })
    end

    it "never lets tenant A read tenant B's key" do
      cache.write(FlowchartRuntime::CacheKey.scoped(1, "user_42"), "secret-a")
      cache.write(FlowchartRuntime::CacheKey.scoped(2, "user_42"), "secret-b")
      ctx = { customer_id: 1 }
      execute(base, ctx)
      expect(ctx[:data]).to eq("secret-a")
      other = { customer_id: 2 }
      execute(base, other)
      expect(other[:data]).to eq("secret-b")
    end

    it "assigns a typed default on a miss" do
      ctx = { customer_id: 1 }
      execute(base.merge("onMiss" => "default", "defaultValue" => "{}"), ctx)
      expect(ctx[:data]).to eq({})
    end

    it "records a translated failure when the tenant is missing" do
      ctx = {}
      result = execute(base, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors].first).to include("Could not read the cache")
    end
  end

  describe "#validate_config" do
    it "requires cacheKey" do
      expect(errors({}).map(&:field)).to include("cacheKey")
    end

    it "rejects a wildcard cacheKey" do
      expect(errors("cacheKey" => "user*").map(&:code)).to include(:wildcard)
    end

    it "rejects a defaultValue that is not one expression when onMiss is default" do
      ["ctx[:a]; Kernel.exit!(1)", "ctx[:a]\nKernel.exit!(1)", "ctx[:a] == ("].each do |payload|
        codes = errors(base.merge("onMiss" => "default", "defaultValue" => payload)).select { |error| error.field.to_s == "defaultValue" }
        expect(codes).not_to be_empty, payload
      end
    end
  end
end
