# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::HashManipulateGenerator do
  let(:context) { {} }
  let(:base) do
    { "sourceVariable" => "data", "operation" => "pick", "keys" => %w[name email], "resultVar" => "payload" }
  end
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"hash_manipulate.failed",
          FlowchartRuntime::HashOps::Error
        ) do
          ctx[:hash] = FlowchartRuntime::HashOps.apply("pick", ctx[:data], keys: ["name", "email"])
          true
        end
      end
    RUBY
  end

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(body(sample)) }.not_to raise_error
  end

  def config_for(operation)
    config = described_class.sample_input.merge("operation" => operation)
    config["otherVariable"] = "overrides" if operation == "merge"
    config["renameMap"] = [{ "key" => "old_name", "value" => "new_name" }] if operation == "rename_keys"
    config["computedFields"] = [{ "key" => "total", "value" => "1 + 1" }] if operation == "set_keys"
    config
  end

  it "lints a BodyLint-clean body for every operation" do
    described_class::OPERATIONS.each do |operation|
      config = config_for(operation)
      expect(errors(config)).to eq([]), "#{operation}: #{errors(config).inspect}"
      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[hash])
      expect(result.ok?).to be(true), "#{operation}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  it "parenthesizes computed values that are not primary expressions" do
    config = config_for("set_keys").merge("computedFields" => [
      { "key" => "total", "value" => "ctx[:a] if ctx[:b]" },
      { "key" => "Display Name", "value" => "ctx[:name]" }
    ])
    expect(body(config)).to include('{total: (ctx[:a] if ctx[:b]), "Display Name" => ctx[:name]}')
    expect { RubyVM::InstructionSequence.compile(body(config)) }.not_to raise_error
  end

  it "emits a distinct body for every operation" do
    bodies = described_class::OPERATIONS.map { |operation| body(config_for(operation)) }
    expect(bodies.uniq.size).to eq(described_class::OPERATIONS.size)
  end

  describe "behaviour" do
    it "picks keys into the result variable" do
      ctx = { data: { "name" => "Ada", "email" => "a@example.test", "secret" => 9 } }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:payload]).to eq("name" => "Ada", "email" => "a@example.test")
    end

    it "renames keys and leaves the source untouched" do
      ctx = { data: { "old_name" => false, "email" => "a@example.test" } }
      original = ctx[:data].dup
      config = base.merge("operation" => "rename_keys",
                          "renameMap" => [{ "key" => "old_name", "value" => "name" }])
      execute(config, ctx)
      expect(ctx[:payload]).to include("name" => false, "email" => "a@example.test")
      expect(ctx[:data]).to eq(original)
    end

    it "merges another hash" do
      ctx = { data: { keep: 1, changed: 2 }, overrides: { changed: 3 } }
      config = base.merge("operation" => "merge", "otherVariable" => "overrides",
                          "mergeStrategy" => "shallow", "onConflict" => "last")
      execute(config, ctx)
      expect(ctx[:payload]).to eq(keep: 1, changed: 3)
    end

    it "compacts nil values" do
      ctx = { data: { "name" => "Ada", "email" => nil } }
      execute(base.merge("operation" => "compact"), ctx)
      expect(ctx[:payload]).to eq("name" => "Ada")
    end

    it "records a translated failure when the source is not a hash" do
      ctx = { data: 12 }
      result = execute(base.merge("operation" => "keys"), ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.hash_manipulate.failed", reason: "Error"))
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable" do
      expect(errors({}).map(&:field)).to include("sourceVariable")
    end

    it "requires keys for pick" do
      expect(errors("sourceVariable" => "x", "operation" => "pick").map(&:field)).to include("keys")
    end

    it "requires otherVariable for merge" do
      expect(errors("sourceVariable" => "x", "operation" => "merge").map(&:field)).to include("otherVariable")
    end

    it "rejects an invalid operation" do
      expect(errors("sourceVariable" => "x", "operation" => "invalid").map(&:code)).to include(:not_in_list)
    end

    it "rejects programmer-only operations" do
      %w[flatten invert deep_dup transform_keys].each do |operation|
        expect(errors("sourceVariable" => "x", "operation" => operation).map(&:code)).to include(:not_in_list)
      end
    end
  end
end
