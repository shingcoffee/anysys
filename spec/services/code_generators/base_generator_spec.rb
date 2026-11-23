# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::BaseGenerator do
  let(:step_action_class) do
    Class.new(CodeGenerators::BaseGenerator) do
      def self.name = "CodeGenerators::ElementTypes::Process::TestStepGenerator"

      generator_metadata do
        description "Test step"
        category :test
        version "1.0.0"
      end

      def generate_body
        "step code: #{config[:testKey]}"
      end

      def validate_config(cfg)
        []
      end
    end
  end

  let(:element_type_class) do
    Class.new(CodeGenerators::BaseGenerator) do
      def self.name = "CodeGenerators::ElementTypes::TestElementGenerator"

      generator_metadata do
        description "Test element"
        category :test
        version "1.0.0"
      end

      def generate_body
        "element code: #{config[:propKey]}"
      end

      def validate_config(cfg)
        []
      end
    end
  end

  def step_gen(element) = step_action_class.new(element, {})

  describe "#initialize" do
    it "extracts config from element['config'] for step actions" do
      gen = step_gen("config" => { "testKey" => "hello" })
      expect(gen.generate_body).to eq("step code: hello")
    end

    it "extracts config from element['properties'] for element types" do
      element = { "properties" => { "propKey" => "world" } }
      gen = element_type_class.new(element, {})
      expect(gen.generate_body).to eq("element code: world")
    end

    it "provides indifferent access to config keys" do
      gen = step_gen("config" => { "testKey" => "value" })
      expect(gen.generate_body).to include("value")
    end

    it "defaults to empty hash when config key is missing" do
      gen = step_gen({})
      expect(gen.generate_body).to eq("step code: ")
    end
  end

  it "does not wrap step-level timeout, retry, or guard keys" do
    expect(described_class.instance_methods(false)).not_to include(
      :apply_wrappers, :wrap_with_timeout, :wrap_with_retry, :wrap_with_guard
    )
    expect(described_class.const_defined?(:MAX_RETRY_BACKOFF_SECONDS)).to be(false)
    gen = step_gen("config" => {}, "timeout" => 5, "retryCount" => 3, "guardCondition" => "ctx[:ready]")
    expect(gen.generate_body).to eq("step code: ")
  end

  describe "emission helpers" do
    def fixture(config = Phase3FixtureGenerator.sample_input)
      Phase3FixtureGenerator.new({ "config" => config }, {})
    end

    it "emits a ctx read for a one-segment input and Step.dig for a nested path" do
      expect(fixture("sourceVariable" => "order").read(:sourceVariable)).to eq("ctx[:order]")
      expect(fixture.read(:sourceVariable)).to eq("FlowchartRuntime::Step.dig(ctx[:order], :items)")
      expect(fixture("sourceVariable" => "order.lines.0.sku").read(:sourceVariable))
        .to eq("FlowchartRuntime::Step.dig(ctx[:order], :lines, 0, :sku)")
    end

    it "refuses to emit unvalidated input paths, output names, and decimals" do
      ["order.items), system(1", "order..items", "order.items-x"].each do |path|
        expect { fixture("sourceVariable" => path).read(:sourceVariable) }
          .to raise_error(CodeGenerators::GeneratorError, /sourceVariable/)
      end
      expect { fixture("resultVar" => "x] = 1; ctx[:y").assign(:resultVar, "1") }
        .to raise_error(CodeGenerators::GeneratorError, /resultVar/)
      expect { fixture("rate" => "1; exit").read(:rate) }
        .to raise_error(CodeGenerators::GeneratorError, /rate/)
    end

    it "emits assign, fail_with, attempt, and body lines" do
      gen = fixture
      expect(gen.assign(:resultVar, "1")).to eq("ctx[:total] = 1")
      expect(gen.fail_with(:empty, field: :sourceVariable, unless: "ctx[:order]"))
        .to eq("return FlowchartRuntime::Step.fail(ctx, :empty, field: :sourceVariable) unless ctx[:order]")
      expect(gen.attempt(:parse, JSON::ParserError) { ["JSON.parse(text)"] })
        .to include("FlowchartRuntime::Step.attempt(ctx, :parse, JSON::ParserError) do")
      expect(gen.body("a", nil, "b")).to eq("a\nb")
    end

    it "emits literals, flags, templates, and parenthesised expressions" do
      gen = fixture
      expect(gen.literal("x")).to eq("\"x\"")
      expect(gen.read(:skipNil)).to eq("true")
      expect(gen.read(:message)).to include("FlowchartRuntime::Template.render")
      expect(gen.read(:predicate)).to eq("(item[:qty] > 0)")
    end

    it "parenthesises an expression only when it is not already a primary" do
      {
        "ctx[:total]" => "ctx[:total]",
        "order.items" => "order.items",
        "order.items.map { |item| item[:qty] }" => "order.items.map { |item| item[:qty] }",
        "Time.current" => "Time.current",
        "42" => "42",
        "[1, 2]" => "[1, 2]",
        "(a + b)" => "(a + b)",
        "a + b" => "(a + b)",
        "!ready" => "(!ready)",
        "a ? b : c" => "(a ? b : c)",
        "puts value" => "(puts value)"
      }.each do |source, emitted|
        expect(fixture("predicate" => source).read(:predicate)).to eq(emitted), source
      end
    end

    it "emits a plain template as a string literal and Liquid markup through the renderer" do
      expect(fixture("message" => "Order shipped").read(:message)).to eq('"Order shipped"')
      expect(fixture("message" => "Hi {{name}}").read(:message))
        .to eq('FlowchartRuntime::Template.render("Hi {{name}}", ctx)')
      expect(fixture("message" => "{% if vip %}VIP{% endif %}").read(:message))
        .to start_with("FlowchartRuntime::Template.render(")
    end

    it "emits conditions as a data literal for the runtime query layer, never as Ruby source" do
      filter = { "type" => "group", "joins" => [], "conditions" => [{ "leftOperand" => "x) || system('id'", "operator" => "is_nil" }] }
      expect(fixture("filter" => filter).read(:filter)).to eq(
        %q{{"type" => "group", "joins" => [], "conditions" => [{"leftOperand" => "x) || system('id'", "operator" => "is_nil"}]}}
      )
      expect(eval(fixture("filter" => filter).read(:filter))).to eq(filter) # rubocop:disable Security/Eval
    end

    it "returns the default for a hidden field from #value" do
      gen = fixture("rateSource" => "live", "fixedRate" => "99")
      expect(gen.value(:fixedRate)).to eq("1.0")
    end

    it "raises GeneratorError when generate_step_method is given invalid Ruby" do
      broken = Class.new(Phase3FixtureGenerator) do
        def self.name = "CodeGenerators::ElementTypes::Process::Utility::Phase3FixtureGenerator"
        def generate_body = "def broken("
      end
      expect { broken.new({ "config" => Phase3FixtureGenerator.sample_input }, {}).generate_step_method }
        .to raise_error(CodeGenerators::GeneratorError, I18n.t("maint_core.flowcharts.generator_error", action: "phase3_fixture"))
    end
  end
end
