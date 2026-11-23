# frozen_string_literal: true

require "rails_helper"
require "support/generator_conformance"

# The registry-wide conformance sweep classifies four property-editor fields as
# :skipped because their values are nested structures rather than scalars, so
# GeneratorConformance cannot synthesise a scalar probe value for them.
# Explicit nested fixtures are needed to prove these fields drive execution.
#
# This spec closes it from both directions:
#   1. a guard that fails if the set of unprobeable fields changes, so a new
#      structural field cannot silently join the blind spot uncovered;
#   2. explicit fixtures for conditions, topology and process composition.
RSpec.describe "unprobeable property-editor fields" do
  # element key => field keys the sweep cannot probe
  COVERED_UNPROBEABLE_FIELDS = {}.freeze

  def structural_fields
    %w[start end process decision loop subflow].each_with_object({}) do |key, acc|
      keys = Array(CodeGenerators::Shared::SchemaReader.read(key)).select { |field|
        GeneratorConformance::UNPROBEABLE_TYPES.include?(field[:type]&.to_sym)
      }.map { |field| field[:key].to_s }
      acc[key] = keys if keys.any?
    end
  end

  it "has hand-written coverage for every field the sweep cannot probe" do
    expect(structural_fields).to eq(COVERED_UNPROBEABLE_FIELDS),
      "The set of unprobeable fields changed. Every field of type " \
      "#{GeneratorConformance::UNPROBEABLE_TYPES.join(', ')} is invisible to the " \
      "registry conformance sweep, so it needs a semantic test in this file. " \
      "Add coverage below, then update COVERED_UNPROBEABLE_FIELDS."
  end

  describe "loop.condition" do
    let(:described_class) { CodeGenerators::ElementTypes::Loop::LoopGenerator }

    def body(properties)
      described_class.new({ "label" => "Loop", "properties" => properties }, {}).generate_body
    end

    def structured(left, operator, right)
      {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }
        ]
      }
    end

    [false, true].each do |run_once|
      it "executes while (runOnceFirst=#{run_once}) with false/true conditions and a bounded iteration count" do
        # Standalone LoopGenerator has no canvas body, so the header iterates
        # internally and returns the Done route. TestRunner records the raw
        # return value; the isolated default done_signal is the symbol :done
        # (wired activities use Routes::<Loop>::Done for the same exit).
        config = {
          "loopType" => "while", "runOnceFirst" => run_once,
          "condition" => structured("ctx.total", "<", "10"), "maxIterations" => 2
        }
        ctx = { total: 20 }
        first = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
        expect(first.fetch(:outcome)).to eq(:done)
        expect(ctx[:_loop_iteration_count]).to eq(run_once ? 1 : 0)
        ctx[:total] = 5
        limited = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
        expect(limited.fetch(:outcome)).to be(false)
        expect(ctx[:_loop_iteration_count]).to eq(2)
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 2)])
      end

      it "compiles a structured condition into the emitted while (runOnceFirst=#{run_once}) body" do
        emitted = body("loopType" => "while", "runOnceFirst" => run_once, "condition" => structured("ctx.total", "<", "10"))

        expect(emitted).to include("total")
        expect(emitted).not_to include("Legacy condition")
        expect { RubyVM::InstructionSequence.compile(emitted) }.not_to raise_error
      end

      it "changes emitted while (runOnceFirst=#{run_once}) source when the condition changes" do
        low  = body("loopType" => "while", "runOnceFirst" => run_once, "condition" => structured("ctx.total", "<", "10"))
        high = body("loopType" => "while", "runOnceFirst" => run_once, "condition" => structured("ctx.total", "<", "999"))

        expect(low).not_to eq(high)
      end
    end

    it "rejects a while loop with no condition" do
      generator = described_class.new({ "label" => "Loop", "properties" => { "loopType" => "while" } }, {})
      expect(generator.validate_config("loopType" => "while").map(&:code)).to include(:required)
    end

    it "rejects a legacy string condition" do
      properties = { "loopType" => "while", "condition" => %(ctx.ok\nKernel.raise("LOOP_INJECTION")) }
      expect(described_class.new({ "properties" => properties }, {}).validate_config(properties).map(&:code))
        .to include(:invalid_conditions)
    end

    it "is hidden for for_each loops, which route through collection instead" do
      field = described_class._config_schema.find_declared("condition")
      expect(field.options[:visible]).to eq("loopType" => "while")
      expect(body("loopType" => "for_each", "collection" => "items"))
        .to eq(body("loopType" => "for_each", "collection" => "items",
                    "condition" => structured("ctx.total", "<", "10")))
    end
  end

  describe "decision.branches" do
    let(:described_class) { CodeGenerators::ElementTypes::Decision::DecisionGenerator }
    def value_props
      { "routeBy" => "value", "subject" => "ctx[:status]" }
    end

    def body(branches)
      described_class.new(
        { "label" => "Decision", "properties" => value_props },
        { flowchart_topology: { outgoing_branches: branches } }
      ).generate_body
    end

    it "emits a when-clause per branch match value" do
      emitted = body([
        { "signal" => "Routes::Decision::Approved", "semantic" => "approved", "matchValue" => "active" },
        { "signal" => "Routes::Decision::Rejected", "semantic" => "rejected", "matchValue" => "banned" },
        { "signal" => "Routes::Decision::Otherwise", "semantic" => "otherwise", "matchValue" => "" }
      ])

      expect(emitted).to include('when "active" then Routes::Decision::Approved')
      expect(emitted).to include('when "banned" then Routes::Decision::Rejected')
      expect(emitted).to include("else Routes::Decision::Otherwise")
    end

    it "changes emitted source when the branch set changes" do
      two = body([
        { "signal" => "Routes::Decision::A", "semantic" => "a", "matchValue" => "x" },
        { "signal" => "Routes::Decision::B", "semantic" => "b", "matchValue" => "" }
      ])
      three = body([
        { "signal" => "Routes::Decision::A", "semantic" => "a", "matchValue" => "x" },
        { "signal" => "Routes::Decision::C", "semantic" => "c", "matchValue" => "y" },
        { "signal" => "Routes::Decision::B", "semantic" => "b", "matchValue" => "" }
      ])

      expect(two).not_to eq(three)
    end

    it "executes the structured subject without topology" do
      { "active" => "active", "banned" => "banned" }.each do |status, value|
        result = CodeGenerators::TestRunner.execute(described_class,
          config: value_props, context: {}, ctx: { status: status })
        expect(result.fetch(:validation_errors)).to be_empty
        expect(result.fetch(:outcome)).to eq(value)
      end
    end

    it "executes a boolean decision condition in both directions without topology" do
      config = {
        "routeBy" => "condition",
        "condition" => {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "kind" => "field", "leftOperand" => "ctx.amount", "operator" => ">", "rightOperand" => "10" }
          ]
        }
      }
      { 11 => true, 10 => false }.each do |amount, value|
        result = CodeGenerators::TestRunner.execute(described_class, config: config, context: {}, ctx: { amount: amount })
        expect(result.fetch(:outcome)).to eq(value)
      end
    end
  end

  describe "process.steps" do
    # `steps` is a container: each entry names a registered step action whose own
    # generator emits the body. It is structural rather than a value the process
    # generator reads, so its conformance guarantee is that every action a user
    # can place in it resolves to a generator.
    it "resolves every selectable step action to a registered generator" do
      action_keys = CodeGenerators::GeneratorRegistry.step_action_generators.keys.map(&:to_s)
      expect(action_keys.size).to eq(96)

      unresolved = action_keys.reject { |key| CodeGenerators::GeneratorRegistry.find_step_action(key) }

      expect(unresolved).to be_empty,
        "Property editor offers step actions with no generator: #{unresolved.join(', ')}"
    end

    it "executes ordered process steps so the second consumes the first output" do
      configuration = {
        "elements" => [
          { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
          { "id" => "p", "type" => "process", "label" => "Work", "properties" => { "steps" => [
            { "action" => "assign_value", "config" => { "resultVar" => "a", "valueType" => "integer", "integerValue" => 7 } }
          ] } },
          { "id" => "p2", "type" => "process", "label" => "Multiply", "properties" => { "steps" => [
            { "action" => "math_operation", "config" => { "operation" => "multiply", "sourceVariable" => "a", "otherVariable" => "b", "resultVar" => "product" } }
          ] } },
          { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
        ],
        "connections" => [
          { "id" => "sp", "from" => "s", "to" => "p" },
          { "id" => "pp", "from" => "p", "to" => "p2" },
          { "id" => "pe", "from" => "p2", "to" => "e" }
        ]
      }
      # Unsaved real model: no DB stub or callbacks persist generated artifacts.
      flowchart = Flowchart.new(name: "QA Process Steps", customer_id: 81721200, configuration: configuration.to_json)
      namespace = Module.new
      namespace.module_eval(ActivityGenerator.new(flowchart).generate)
      activity = namespace.const_get(:QaProcessStepsActivity)
      signal, (ctx, _) = activity.call([{ b: 3 }, {}])
      expect(signal.to_h.fetch(:semantic)).to eq(:success)
      expect(ctx).to include(a: 7, product: 21.0)
    end
  end
end
