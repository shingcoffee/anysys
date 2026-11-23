# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("scripts/audit_generators.rb")
fixture_paths = Dir[Rails.root.join("spec/fixtures/audit_generators/*.rb")]
clean_fixture = fixture_paths.find { |path| path.end_with?("clean_generator_fixture.rb") }
load clean_fixture
(fixture_paths - [clean_fixture]).each { |path| load path }

RSpec.describe GeneratorAudit do
  def run_for(klass)
    described_class.check_generator(klass)
  end

  def gaps_for(klass, rule)
    run_for(klass).select { |g| g[:rule] == rule }
  end

  describe ".check_generator returns gaps as an Array of Hashes" do
    it "returns an Array" do
      expect(run_for(AuditFixtures::CleanGenerator)).to be_an(Array)
    end

    it "each gap has :rule, :message, :file keys" do
      result = run_for(AuditFixtures::LegacyAliasGenerator)
      expect(result).not_to be_empty
      gap = result.first
      expect(gap).to include(:rule, :message, :file)
    end
  end

  describe "rule 2: bracket-notation ctx access" do
    it "passes for a generator using ctx[:key] reads only" do
      expect(gaps_for(AuditFixtures::CleanGenerator, :ctx_access)).to be_empty
    end

    it "flags a generator that emits ctx.foo dotted access" do
      gaps = gaps_for(AuditFixtures::DottedCtxGenerator, :ctx_access)
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to include("ctx.")
    end
  end

  describe "rule 4: no inline multi-step orchestration" do
    it "passes for a clean generator" do
      expect(gaps_for(AuditFixtures::CleanGenerator, :inline_orchestration)).to be_empty
    end

    it "passes for a thin-wrapper generator (single ActivitySteps:: call is the body)" do
      expect(gaps_for(AuditFixtures::ThinWrapperGenerator, :inline_orchestration)).to be_empty
    end

    it "flags a generator with TWO ActivitySteps:: calls in one body" do
      gaps = gaps_for(AuditFixtures::InlineOrchestrationGenerator, :inline_orchestration)
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to match(/multiple .* orchestration/i)
    end
  end

  describe "rule 5: no legacy alias reads" do
    it "passes for a clean generator" do
      expect(gaps_for(AuditFixtures::CleanGenerator, :legacy_alias)).to be_empty
    end

    it "flags config[\"X\"] || config[\"Y\"] patterns" do
      gaps = gaps_for(AuditFixtures::LegacyAliasGenerator, :legacy_alias)
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to include("strategy")
      expect(gaps.first[:message]).to include("saveStrategy")
    end
  end

  describe "rule 7: enum validation uses fetch_enum" do
    it "passes for a clean generator" do
      expect(gaps_for(AuditFixtures::CleanGenerator, :enum_handling)).to be_empty
    end

    it "flags %w[...].include?(...) inside generate_body" do
      expect(gaps_for(AuditFixtures::HandRolledEnumGenerator, :enum_handling)).not_to be_empty
    end

    it "flags a hand-rolled enum that follows a heredoc and a nested block" do
      klass = AuditFixtures::HeredocNestedEnumGenerator

      expect(gaps_for(klass, :enum_handling)).to contain_exactly(
        include(message: include("#generate_body"))
      )
    end

    it "flags build_* methods across nested blocks and heredocs but excludes validate_config" do
      gaps = gaps_for(AuditFixtures::NestedEnumGenerator, :enum_handling)

      expect(gaps.size).to eq(1)
      expect(gaps.first.fetch(:message)).to include("#build_fragment")
      expect(gaps.first.fetch(:message)).not_to include("#validate_config")
    end
  end

  describe "rule 8: dependencies reflects ctx reads" do
    it "passes for a generator with correct dependencies" do
      expect(gaps_for(AuditFixtures::CleanGenerator, :dependencies)).to be_empty
    end

    it "flags a body that reads ctx[:contract] without declaring :build_contract" do
      gaps = gaps_for(AuditFixtures::MissingDependencyGenerator, :dependencies)
      expect(gaps).not_to be_empty
      expect(gaps.first[:message]).to include("contract")
    end
  end

  describe "rule 9: no forbidden emitted source" do
    it "ignores forbidden text that exists only in generator source comments or strings" do
      expect(gaps_for(AuditFixtures::ForbiddenSourceOnlyGenerator, :unsafe_marshal)).to be_empty
    end

    it "does not let generated code authorize its own forbidden emission" do
      gaps = gaps_for(AuditFixtures::SelfAuthorizingGeneratedGenerator, :unsafe_marshal)

      expect(gaps.size).to eq(1)
      expect(gaps.first).not_to have_key(:allowed)
    end

    it "accepts an allow directive from an actual generator source comment" do
      gaps = gaps_for(AuditFixtures::AllowedForbiddenEmissionGenerator, :unsafe_marshal)

      expect(gaps).to contain_exactly(
        include(
          allowed: true,
          reason: "compatibility payload is trusted and versioned"
        )
      )
    end

    it "exercises both flag values, skips string booleans the schema rejects, and dedupes configs and bodies" do
      klass = CodeGenerators::ElementTypes::Process::DataOperations::LogGenerator
      variants = described_class.send(:configuration_variants, klass)
      configs = variants.map { |variant| variant.fetch(:config) }
      backtrace_values = configs.map { |config| config.fetch("includeBacktrace") }.uniq
      generated = described_class.send(:generated_variants, klass)

      expect(backtrace_values).to contain_exactly(true, false)
      expect(configs).to eq(configs.uniq)
      expect(generated.map { |variant| variant.fetch(:body) }).to eq(
        generated.map { |variant| variant.fetch(:body) }.uniq
      )
    end

    it "accepts CloneModelGenerator because it delegates copying to the runtime facade" do
      klass = CodeGenerators::ElementTypes::Process::ModelOperations::CloneModelGenerator

      expect(gaps_for(klass, :unsafe_marshal)).to be_empty
      generated = described_class.send(:generated_variants, klass)
      expect(generated.map { |variant| variant.fetch(:body) }).to all(include("FlowchartRuntime::Clone.copy"))
    end
  end

  describe "visibility-dependent conditions fields" do
    it "terminates for a conditions field that is only visible in one mode" do
      loop_generator = CodeGenerators::ElementTypes::Loop::LoopGenerator
      variants = Timeout.timeout(10) { GeneratorAudit.send(:generated_variants, loop_generator) }

      expect(variants).not_to be_empty
    end
  end

  describe "configuration-dependent emission variants" do
    let(:variant_class) do
      Class.new do
        include CodeGenerators::GeneratorInterface

        def self.name
          "CodeGenerators::ElementTypes::Process::Audit::VariantGenerator"
        end

        config_schema do
          flag :enabled
          enum :mode, %w[first second]
        end

        def self.sample_input
          { "enabled" => false, "mode" => "first", "stable" => "value" }
        end

        def generate_body
          config = @element.fetch("config")
          "enabled=#{config.fetch('enabled')};mode=#{config.fetch('mode')}"
        end
      end
    end

    let(:conditional_variant_class) do
      Class.new do
        include CodeGenerators::GeneratorInterface

        def self.name
          "CodeGenerators::ElementTypes::Process::Audit::ConditionalVariantGenerator"
        end

        config_schema do
          enum :mode, %w[basic advanced]
          literal :alwaysRequired
          literal :sampleDependent
          literal :schemaDefault, default: "generator_fallback"
          literal :generatorDefault, default: "generator_default"
          integer :numberValue, min: 2
          literal :selectValue
          literal :pairs

          validate do |cfg, errors|
            errors << "alwaysRequired is required" if cfg["alwaysRequired"].blank?
            next unless cfg["mode"] == "advanced"

            %w[
              sampleDependent schemaDefault generatorDefault numberValue selectValue pairs
            ].each do |key|
              errors << "#{key} is required" if cfg[key].blank?
            end
          end
        end

        def self.sample_input
          { "mode" => "basic", "sampleDependent" => "sample_value" }
        end

        def generate_body
          @element.fetch("config").inspect
        end
      end
    end

    it "uses serialized builder values and adds deterministic pairwise overrides" do
      allow(described_class).to receive(:ui_config_fields_for).with(variant_class).and_return(
        [
          {
            key: "enabled",
            type: :select,
            default: "false",
            options: [{ "value" => "false" }, { "value" => "true" }]
          },
          {
            key: "mode",
            type: :select,
            default: "first",
            options: [{ "value" => "first" }, { "value" => "second" }]
          }
        ]
      )

      variants = described_class.send(:configuration_variants, variant_class)

      expect(variants.map { |variant| variant.fetch(:label) }).to eq(
        [
          "sample_input",
          "enabled=true",
          "mode=second",
          "enabled=true + mode=second"
        ]
      )
      expect(variants.find { |variant| variant[:label] == "enabled=true" }.fetch(:config)).to include(
        "enabled" => true,
        "mode" => "first",
        "stable" => "value"
      )
      expect(variants.find { |variant| variant[:label] == "mode=second" }.fetch(:config)).to include(
        "enabled" => false,
        "mode" => "second",
        "stable" => "value"
      )
    end

    it "exercises both Ruby booleans for every flag field" do
      allow(described_class).to receive(:ui_config_fields_for).with(variant_class).and_return(
        [{ key: "enabled", type: :checkbox, default: false }]
      )

      values = described_class.send(:configuration_variants, variant_class)
        .map { |variant| variant.fetch(:config).fetch("enabled") }
        .uniq

      expect(values).to contain_exactly(true, false)
    end

    it "covers the LogGenerator error backtrace branch with a labeled pairwise variant" do
      variants = described_class.send(
        :configuration_variants,
        CodeGenerators::ElementTypes::Process::DataOperations::LogGenerator
      )
      combined = variants.find do |variant|
        variant[:label].start_with?("logLevel=error + includeBacktrace=true")
      end

      expect(combined).to include(config: include("logLevel" => "error", "includeBacktrace" => true))
    end

    it "does not audit removed structural generators" do
      report = described_class.run_audit

      expect(report.keys).not_to include(
        "CodeGenerators::ElementTypes::Fork::ForkGenerator",
        "CodeGenerators::ElementTypes::Join::JoinGenerator",
        "CodeGenerators::ElementTypes::ParallelForEach::ParallelForEachGenerator",
        "CodeGenerators::ElementTypes::Saga::SagaGenerator",
        "CodeGenerators::ElementTypes::SignalWait::SignalWaitGenerator",
        "CodeGenerators::ElementTypes::Transaction::TransactionGenerator"
      )
    end

    it "uses deterministic value priorities for visible dependent fields" do
      allow(described_class).to receive(:ui_config_fields_for).with(conditional_variant_class).and_return(
        [
          {
            key: "mode",
            type: :select,
            default: "basic",
            options: [{ "value" => "basic" }, { "value" => "advanced" }]
          },
          {
            key: "alwaysRequired",
            type: :text,
            required: true
          },
          {
            key: "sampleDependent",
            type: :text,
            required: true,
            visibleWhen: { "field" => "mode", "value" => "advanced" }
          },
          {
            key: "schemaDefault",
            type: :text,
            required: true,
            default: "schema_default",
            visibleWhen: { "field" => "mode", "values" => ["advanced"] }
          },
          {
            key: "generatorDefault",
            type: :text,
            required: true,
            visibleWhen: { "field" => "mode", "value" => "advanced" }
          },
          {
            key: "numberValue",
            type: :number,
            required: true,
            min: 2,
            visibleWhen: { "field" => "mode", "value" => "advanced" }
          },
          {
            key: "selectValue",
            type: :select,
            required: true,
            options: [{ "value" => "" }, { "value" => "selected" }],
            visibleWhen: { "field" => "mode", "value" => "advanced" }
          },
          {
            key: "pairs",
            type: :key_value_list,
            required: true,
            visibleWhen: { "field" => "mode", "value" => "advanced" }
          }
        ]
      )

      variant = described_class.send(:generated_variants, conditional_variant_class)
        .find { |candidate| candidate[:label] == "mode=advanced" }
      config = variant.fetch(:element).fetch("config")

      expect(config).to include(
        "alwaysRequired" => "audit_value",
        "sampleDependent" => "sample_value",
        "schemaDefault" => "schema_default",
        "generatorDefault" => "generator_default",
        "numberValue" => 2,
        "selectValue" => "selected",
        "pairs" => [{ "key" => "audit", "value" => "audit_value" }]
      )
    end

    it "prioritizes actual conditional trigger values within the pairwise cap" do
      allow(described_class).to receive(:ui_config_fields_for).with(variant_class).and_return(
        [
          {
            key: "mode",
            type: :select,
            default: "first",
            options: [
              { "value" => "first" },
              { "value" => "second" },
              { "value" => "third" }
            ]
          },
          {
            key: "enabled",
            type: :select,
            default: "false",
            options: [
              { "value" => "false" },
              { "value" => "true" }
            ]
          },
          {
            key: "details",
            type: :text,
            visibleWhen: { "field" => "mode", "value" => "second" }
          }
        ]
      )
      stub_const("GeneratorAudit::MAX_PAIRWISE_VARIANTS_PER_GENERATOR", 1)

      labels = described_class.send(:configuration_variants, variant_class).map { |variant| variant.fetch(:label) }

      expect(labels.last).to eq("enabled=true + mode=second")
    end

    it "uses every UI option for fields controlling conditional inputs" do
      allow(described_class).to receive(:ui_config_fields_for).with(variant_class).and_return(
        [
          {
            key: "authType",
            type: :select,
            options: [{ "value" => "none" }, { "value" => "bearer" }, { "value" => "basic" }]
          },
          { key: "authToken", type: :text, visibleWhen: { "field" => "authType", "value" => "bearer" } }
        ]
      )

      expect(described_class.send(:conditional_ui_variant_values, variant_class)).to eq(
        "authType" => %w[bearer none basic]
      )
    end

    it "deduplicates variants that emit identical bodies" do
      allow(described_class).to receive(:configuration_variants).with(variant_class).and_return(
        [
          { label: "sample_input", config: variant_class.sample_input },
          { label: "enabled=false", config: variant_class.sample_input.dup }
        ]
      )

      expect(described_class.send(:generated_variants, variant_class).map { |variant| variant[:label] }).to eq(
        ["sample_input"]
      )
    end

    it "returns an actionable generation_error when a variant raises" do
      gaps = gaps_for(AuditFixtures::RaisingVariantGenerator, :generation_error)

      expect(gaps).to contain_exactly(
        include(
          generator: "AuditFixtures::RaisingVariantGenerator",
          variant: "mode=explode",
          exception_class: "ArgumentError",
          exception_message: "intentional explode variant",
          message: include("mode=explode", "ArgumentError", "intentional explode variant")
        )
      )
    end

    it "skips validation-failing variants without generating or auditing their bodies" do
      klass = AuditFixtures::ValidationErrorVariantGenerator
      klass.generated_modes = []

      variants = described_class.send(:configuration_variants, klass)
      gaps = run_for(klass)

      expect(variants.map { |variant| variant.fetch(:label) }).to eq(["sample_input"])
      expect(gaps.select { |gap| gap[:rule] == :generation_error }).to be_empty
      expect(gaps.select { |gap| gap[:rule] == :unsafe_marshal }).to be_empty
      expect(klass.generated_modes).to eq(["safe"])
    end

    it "accepts a nil generated body without reporting a generation error" do
      variants = described_class.send(:generated_variants, AuditFixtures::NilBodyGenerator)

      expect(variants).to contain_exactly(
        include(label: "sample_input", body: nil)
      )
      expect(gaps_for(AuditFixtures::NilBodyGenerator, :generation_error)).to be_empty
    end

    it "reports a generation error for an invalid non-nil generated body type" do
      expect(gaps_for(AuditFixtures::InvalidBodyTypeGenerator, :generation_error)).to contain_exactly(
        include(
          generator: "AuditFixtures::InvalidBodyTypeGenerator",
          variant: "sample_input",
          exception_class: "GeneratorAudit::UnusableOutputError",
          exception_message: "generate_body returned Hash; expected String or nil"
        )
      )
    end
  end

  describe ".run_audit scans the live codebase" do
    it "returns a hash keyed by generator class name" do
      report = described_class.run_audit
      expect(report).to be_a(Hash)
      expect(report.keys).to all(be_a(String))
    end

    it "produces an empty or populated :gaps array for each entry" do
      report = described_class.run_audit
      report.each_value do |entry|
        expect(entry).to have_key(:gaps)
        expect(entry[:gaps]).to be_an(Array)
      end
    end
  end
end
