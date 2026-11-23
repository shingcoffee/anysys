# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "compound conditions" do
  let_it_be(:customer) { create(:customer) }

  def field_row(left, operator, right = "")
    { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }
  end

  def build_loop_flowchart(condition:, maxIterations: 10)
    config = {
      "elements" => [
        { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
          "label" => "Start", "properties" => {} },
        { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
          "label" => "Check Loop", "properties" => {
            "loopType" => "while",
            "condition" => condition,
            "maxIterations" => maxIterations
          } },
        { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
          "label" => "End", "properties" => { "responseType" => "none" } }
      ],
      "connections" => [
        { "id" => "conn_1", "from" => "el_start", "to" => "el_loop" },
        { "id" => "conn_2", "from" => "el_loop", "to" => "el_end" }
      ],
      "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
    }
    Flowchart.new(name: "Compound Loop", customer: customer, configuration: config.to_json)
  end

  let(:code) { described_class.new(build_loop_flowchart(condition: condition)).generate }

  describe "AND compound condition" do
    let(:condition) do
      {
        "type" => "group",
        "joins" => ["AND"],
        "conditions" => [
          field_row("ctx.model.status", "==", "active"),
          field_row("ctx.model.role", "!=", "guest")
        ]
      }
    end

    it "generates && in Ruby for AND compound condition in loop" do
      expect(code).to include("&&")
      expect(code).to include('FlowchartRuntime::Step.dig(ctx[:model], :status) == "active"')
      expect(code).to include('FlowchartRuntime::Step.dig(ctx[:model], :role) != "guest"')
    end

    it "wraps compound conditions in parentheses with && operator" do
      expect(code).to include('(FlowchartRuntime::Step.dig(ctx[:model], :status) == "active" && FlowchartRuntime::Step.dig(ctx[:model], :role) != "guest")')
    end
  end

  describe "OR compound condition" do
    let(:condition) do
      {
        "type" => "group",
        "joins" => ["OR"],
        "conditions" => [
          field_row("ctx.model.status", "==", "active"),
          field_row("ctx.model.status", "==", "pending")
        ]
      }
    end

    it "generates || in Ruby for OR compound condition" do
      expect(code).to include("||")
      expect(code).to include('FlowchartRuntime::Step.dig(ctx[:model], :status) == "active"')
      expect(code).to include('FlowchartRuntime::Step.dig(ctx[:model], :status) == "pending"')
    end

    it "executes when only the second OR operand is true" do
      namespace = Module.new
      namespace.module_eval(code)
      signal, (ctx, _) = namespace.const_get(:CompoundLoopActivity).call([{ model: { status: "pending" } }, {}])
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:_loop_iteration_count]).to eq(10)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 10)])
    end
  end

  describe "single condition in group" do
    let(:condition) do
      {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          field_row("ctx.model.age", ">", "18")
        ]
      }
    end

    it "generates a single condition without wrapping parentheses or joining operators" do
      expect(code).to match(
        /FlowchartRuntime::ConditionInput\.compare\(\s*FlowchartRuntime::Step\.dig\(ctx\[:model\], :age\),\s*">",\s*18\s*\)/
      )
      expect(code).not_to include(" && ")
    end
  end

  describe "empty group" do
    let(:condition) do
      {
        "type" => "group",
        "joins" => [],
        "conditions" => []
      }
    end

    it "rejects an empty while condition group as an error" do
      record = build_loop_flowchart(condition: condition)
      expect { described_class.new(record).generate }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
        expect(error.details.map(&:code)).to include(:empty_condition)
      }
    end
  end

  describe "nested groups" do
    let(:condition) do
      {
        "type" => "group",
        "joins" => ["AND"],
        "conditions" => [
          field_row("ctx.model.active", "is_true"),
          {
            "type" => "group",
            "joins" => ["OR"],
            "conditions" => [
              field_row("ctx.model.role", "==", "admin"),
              field_row("ctx.model.role", "==", "manager")
            ]
          }
        ]
      }
    end

    it "rejects nested condition groups" do
      record = build_loop_flowchart(condition: condition)
      expect { described_class.new(record).generate }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
        expect(error.details.map(&:code)).to include(:nested_group)
      }
    end
  end

  describe "legacy single condition" do
    let(:condition) do
      {
        "leftOperand" => "ctx.retry_count",
        "operator" => "<",
        "rightOperand" => "3"
      }
    end

    it "rejects a bare comparison that is not a condition group" do
      record = build_loop_flowchart(condition: condition)
      expect { described_class.new(record).generate }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
        expect(error.details.map(&:code)).to include(:invalid_condition)
      }
    end
  end

  describe "compound condition with unary operators" do
    let(:condition) do
      {
        "type" => "group",
        "joins" => ["AND"],
        "conditions" => [
          field_row("ctx.model.name", "is_not_empty"),
          field_row("ctx.model.active", "is_true")
        ]
      }
    end

    it "generates correct Ruby for unary operators in compound condition" do
      expect(code).to include("FlowchartRuntime::Step.dig(ctx[:model], :name).present?")
      expect(code).to include("!!FlowchartRuntime::Step.dig(ctx[:model], :active)")
      expect(code).to include("&&")
    end
  end
end
