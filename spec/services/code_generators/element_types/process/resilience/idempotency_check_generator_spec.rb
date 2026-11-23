# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Resilience::IdempotencyCheckGenerator do
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
          :"idempotency_check.failed",
          FlowchartRuntime::Idempotency::Error,
          FlowchartRuntime::CacheKey::Error,
          FlowchartRuntime::Template::Error
        ) do
          claimed = FlowchartRuntime::Idempotency.claim(ctx, ctx[:order_id].to_s, ttl: 3600)
          ctx[:idempotency_result] = claimed
          return FlowchartRuntime::Step.fail(ctx, :duplicate_request) unless claimed == :claimed
          claimed
        end
      end
    RUBY
  end

  it "emits skip without a duplicate_request fail" do
    code = generated_step(described_class.sample_input.merge("onDuplicate" => "skip"))
    expect(code).not_to include("duplicate_request")
    expect(code).to include("claimed = FlowchartRuntime::Idempotency.claim")
  end

  it "emits flag as the claimed value" do
    code = generated_step(described_class.sample_input.merge("onDuplicate" => "flag"))
    expect(code).not_to include("duplicate_request")
    expect(code).to include("ctx[:idempotency_result] = claimed")
    expect(code).not_to include("unless claimed == :claimed")
  end

  it "emits user-scope guard and scope kwarg" do
    code = generated_step(described_class.sample_input.merge("scope" => "user"))
    expect(code).to include('scope: "user"')
    expect(code).to include("return false unless claimed")
  end

  it "emits hash_of_inputs and explicit key strategies" do
    hash_code = generated_step(described_class.sample_input.merge("keyStrategy" => "hash_of_inputs"))
    expect(hash_code).to include("FlowchartRuntime::Idempotency.digest_inputs(ctx[:params])")
    explicit = generated_step(described_class.sample_input.merge("keyStrategy" => "explicit", "explicitKey" => "order:42"))
    expect(explicit).to include('claim(ctx, "order:42", ttl: 3600)')
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "emits a BodyLint-clean body for each keyStrategy" do
    {
      "ctx_field" => { "ctxField" => "order_id" },
      "hash_of_inputs" => {},
      "explicit" => { "explicitKey" => "order:42" }
    }.each do |strategy, extra|
      config = described_class.sample_input.merge("keyStrategy" => strategy).merge(extra)
      next if errors(config).any?

      result = CodeGenerators::BodyLint.check(generate(config), outputs: %w[idempotency_result])
      expect(result.ok?).to be(true), "#{strategy}: #{result.violations.inspect}\n#{generate(config)}"
    end
  end

  describe "behaviour" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "claims once and fails a duplicate with a translated message" do
      config = described_class.sample_input.merge("keyStrategy" => "ctx_field", "ctxField" => "order_id")
      first = { customer_id: 41, order_id: "A-1", errors: [] }
      second = { customer_id: 41, order_id: "A-1", errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: first)[:outcome]).to eq(:claimed)
      denied = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: second)
      expect(denied[:outcome]).to be(false)
      expect(second[:errors]).to eq([I18n.t("flowchart_runtime.errors.duplicate_request")])
    end

    it "does not share keys across tenants" do
      config = described_class.sample_input.merge("explicitKey" => "order:42", "keyStrategy" => "explicit")
      own = { customer_id: 41, errors: [] }
      other = { customer_id: 99, errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: own)[:outcome]).to eq(:claimed)
      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: other)[:outcome]).to eq(:claimed)
    end

    it "flags a duplicate without failing when onDuplicate is flag" do
      config = described_class.sample_input.merge(
        "keyStrategy" => "explicit", "explicitKey" => "order:42", "onDuplicate" => "flag"
      )
      first = { customer_id: 41, errors: [] }
      second = { customer_id: 41, errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: first)[:outcome]).to eq(:claimed)
      again = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: second)
      expect(again[:outcome]).to eq(:duplicate)
      expect(second[:errors]).to be_blank
    end

    it "does not share user-scoped keys across users of the same tenant" do
      config = described_class.sample_input.merge(
        "keyStrategy" => "explicit", "explicitKey" => "order:42", "scope" => "user"
      )
      alice = { customer_id: 41, current_user_id: 7, errors: [] }
      bob = { customer_id: 41, current_user_id: 8, errors: [] }

      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: alice)[:outcome]).to eq(:claimed)
      expect(CodeGenerators::TestRunner.execute(described_class, config: config, ctx: bob)[:outcome]).to eq(:claimed)
    end

    it "fails user-scoped checks when no user is signed in" do
      config = described_class.sample_input.merge(
        "keyStrategy" => "explicit", "explicitKey" => "order:42", "scope" => "user"
      )
      ctx = { customer_id: 41, errors: [] }
      denied = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
      expect(denied[:outcome]).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.idempotency_user_required")])
    end
  end
end
