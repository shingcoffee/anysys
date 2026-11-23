# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::DataOperations::MapValueGenerator do
  let(:context) { {} }
  let(:base) do
    {
      "sourceVariable" => "status",
      "resultVar" => "label",
      "mappings" => [{ "key" => "draft", "value" => "Draft" }, { "key" => "published", "value" => "Live" }],
      "defaultValue" => "Unknown"
    }
  end
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
        FlowchartRuntime::Step.attempt(ctx, :"map_value.failed", FlowchartRuntime::ValueMap::Error) do
          ctx[:mapped_value] = FlowchartRuntime::ValueMap.apply(
            ctx[:status],
            match_mode: "exact",
            mappings: {"active" => "Active", "inactive" => "Inactive"},
            default: "Unknown"
          )
          true
        end
      end
    RUBY
  end

  it "generates a regex rules step" do
    config = described_class.sample_input.merge(
      "matchMode" => "regex",
      "rules" => [{ "key" => "^a", "value" => "starts-a" }]
    )
    expect(generated_step(config)).to include('match_mode: "regex"')
    expect(generated_step(config)).to include('rules: [{"pattern" => "^a", "value" => "starts-a"}]')
    expect(generated_step(config)).not_to include("mappings:")
  end

  it "emits fallback: raise when configured" do
    expect(generated_step(described_class.sample_input.merge("fallbackStrategy" => "raise")))
      .to include('fallback: "raise"')
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "does not expose multiMatch" do
    expect(described_class._config_schema.find_declared("multiMatch")).to be_nil
  end

  it "lints a BodyLint-clean body for every matchMode and fallbackStrategy" do
    described_class::MATCH_MODES.product(described_class::FALLBACK_STRATEGIES).each do |mode, fallback|
      config = described_class.sample_input.merge("matchMode" => mode, "fallbackStrategy" => fallback)
      next if errors(config).any?

      result = CodeGenerators::BodyLint.check(body(config), outputs: %w[mapped_value])
      expect(result.ok?).to be(true), "#{mode}/#{fallback}: #{result.violations.inspect}\n#{body(config)}"
    end
  end

  describe "behaviour" do
    it "maps an exact value and uses the default" do
      ctx = { status: "unknown" }
      result = execute(base, ctx)
      expect(result[:outcome]).to be_truthy
      expect(ctx[:label]).to eq("Unknown")
    end

    it "maps a regex rule case-insensitively" do
      ctx = { status: "AbC" }
      config = base.merge("matchMode" => "regex", "caseSensitive" => false,
                          "rules" => [{ "key" => "^ABC$", "value" => "upper" }])
      execute(config, ctx)
      expect(ctx[:label]).to eq("upper")
    end

    it "records a translated failure on raise fallback" do
      ctx = { status: "missing" }
      result = execute(base.merge("fallbackStrategy" => "raise", "defaultValue" => nil), ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.map_value.failed", reason: "Error"))
    end
  end

  describe "#validate_config" do
    it "requires sourceVariable and mappings in exact mode" do
      fields = errors({}).map(&:field)
      expect(fields).to include("sourceVariable", "mappings")
    end

    it "requires rules for regex mode" do
      expect(errors("sourceVariable" => "a", "matchMode" => "regex").map(&:field)).to include("rules")
    end
  end
end
