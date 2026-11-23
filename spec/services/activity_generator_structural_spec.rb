# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "retained structural semantics" do
  def flowchart_double(elements, connections, name: "Structural Flow")
    instance_double(
      Flowchart,
      id: 999_999,
      name: name,
      elements: elements,
      connections: connections,
      customer_id: nil,
      shared?: false,
      customer_owned?: true
    )
  end

  it "passes Decision routing topology through generator context and rejects duplicate match values" do
    elements = [
      { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
      {
        "id" => "d",
        "type" => "decision",
        "label" => "Route",
        "properties" => {
          "routeBy" => "value",
          "subject" => "ctx[:status]",
          "defaultBranchIndex" => 2,
          "_connection_match_values" => [{ "branch" => "client_branch", "matchValue" => "ignored" }]
        }
      },
      { "id" => "a", "type" => "process", "label" => "A", "properties" => { "steps" => [] } },
      { "id" => "b", "type" => "process", "label" => "B", "properties" => { "steps" => [] } },
      { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
    ]
    connections = [
      { "id" => "c1", "from" => "s", "to" => "d" },
      { "id" => "c2", "from" => "d", "to" => "a", "matchValue" => "active" },
      { "id" => "c3", "from" => "d", "to" => "b", "matchValue" => "active" },
      { "id" => "c4", "from" => "a", "to" => "e" },
      { "id" => "c5", "from" => "b", "to" => "e" }
    ]

    expect { described_class.new(flowchart_double(elements, connections)).generate }
      .to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
        expect(error.element_id).to eq("d")
        expect(error.details.map(&:to_s)).to include("Match values must be unique")
      }
  end

  it "rejects Decision conditions that ConditionBuilder would reduce to true" do
    invalid_conditions = [
      {
        condition: { "type" => "group", "joins" => [], "conditions" => [] },
        expected_error: "Add at least one condition"
      },
      {
        condition: {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "kind" => "field", "leftOperand" => " ", "operator" => "==", "rightOperand" => "x" }
          ]
        },
        expected_error: "Condition row 1 needs a value to compare"
      }
    ]

    invalid_conditions.each do |example|
      elements = [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        {
          "id" => "d",
          "type" => "decision",
          "label" => "Route",
          "properties" => { "routeBy" => "condition", "condition" => example.fetch(:condition) }
        },
        { "id" => "a", "type" => "process", "label" => "A", "properties" => { "steps" => [] } },
        { "id" => "b", "type" => "process", "label" => "B", "properties" => { "steps" => [] } },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
      ]
      connections = [
        { "id" => "c1", "from" => "s", "to" => "d" },
        { "id" => "c2", "from" => "d", "to" => "a", "matchValue" => "active" },
        { "id" => "c3", "from" => "d", "to" => "b", "matchValue" => "" },
        { "id" => "c4", "from" => "a", "to" => "e" },
        { "id" => "c5", "from" => "b", "to" => "e" }
      ]

      expect { described_class.new(flowchart_double(elements, connections)).generate }
        .to raise_error(ActivityGenerator::Error) { |error|
          expect(error.code).to eq(:invalid_generator_config)
          expect(error.element_id).to eq("d")
          expect(error.details.map(&:to_s)).to include(example.fetch(:expected_error))
        }
    end
  end

  it "uses server topology instead of editable Decision route and match properties" do
    elements = [
      { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
      {
        "id" => "d",
        "type" => "decision",
        "label" => "Route",
        "properties" => {
          "routeBy" => "value",
          "subject" => "ctx[:status]"
        }
      },
      { "id" => "a", "type" => "process", "label" => "A", "properties" => { "steps" => [] } },
      { "id" => "b", "type" => "process", "label" => "B", "properties" => { "steps" => [] } },
      { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
    ]
    connections = [
      { "id" => "c1", "from" => "s", "to" => "d" },
      { "id" => "c2", "from" => "d", "to" => "a", "matchValue" => "active" },
      { "id" => "c3", "from" => "d", "to" => "b", "matchValue" => "" },
      { "id" => "c4", "from" => "a", "to" => "e" },
      { "id" => "c5", "from" => "b", "to" => "e" }
    ]

    code = described_class.new(flowchart_double(elements, connections)).generate

    expect(code).to include("Routes::Route")
    expect(code).to include('when "active" then Routes::Route::Active')
    expect(code).not_to include("ctx[:_route_")
    expect(code).not_to include("ROUTE_INJECTION")
    expect(code).not_to include("client_branch")
    expect(code).not_to include("client_value")
    expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
  end

  it "executes a synchronous inline Subprocess with shared context" do
    customer = create(:customer)
    target = create(:flowchart, customer: customer, name: "Mapped Child")
    parent = create(:flowchart, customer: customer, name: "Mapped Parent")
    allow(parent).to receive(:elements).and_return([
      { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
      {
        "id" => "sf",
        "type" => "subflow",
        "label" => "Child",
        "properties" => {
          "flowchartId" => target.id
        }
      },
      { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
    ])
    allow(parent).to receive(:connections).and_return([
      { "id" => "c1", "from" => "s", "to" => "sf" },
      { "id" => "c2", "from" => "sf", "to" => "e" }
    ])

    code = described_class.new(parent).generate
    expect(code).to include("step Subprocess(MappedChildActivity)")
    expect(code).not_to include("In()")
    expect(code).not_to include("Out()")
    expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error

    Object.send(:remove_const, :MappedChildActivity) if Object.const_defined?(:MappedChildActivity)
    Object.const_set(
      :MappedChildActivity,
      Class.new(Trailblazer::Activity::Railway) do
        step :copy_result

        def copy_result(ctx, **)
          ctx[:child_result] = "child-#{ctx[:order_id]}"
          true
        end
      end
    )
    Object.send(:remove_const, :MappedParentActivity) if Object.const_defined?(:MappedParentActivity)
    eval(code) # rubocop:disable Security/Eval

    _signal, (ctx, _) = MappedParentActivity.call([{ order_id: "42" }, {}])
    expect(ctx[:child_result]).to eq("child-42")
  ensure
    Object.send(:remove_const, :MappedParentActivity) if Object.const_defined?(:MappedParentActivity)
    Object.send(:remove_const, :MappedChildActivity) if Object.const_defined?(:MappedChildActivity)
  end

  it "rejects every removed structural type before adversarial source can be emitted" do
    ActivityGenerator::StructureValidator::UNSUPPORTED_STRUCTURAL_TYPES.each do |type|
      elements = [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        {
          "id" => "x",
          "type" => type,
          "label" => "Unsafe\nKernel.raise(\"LABEL_INJECTION\")",
          "properties" => {
            "signalName" => "approval\"\nKernel.raise(\"SIGNAL_INJECTION\")",
            "condition" => "Kernel.raise(\"CONDITION_INJECTION\")"
          }
        },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
      ]
      connections = [
        { "id" => "c1", "from" => "s", "to" => "x" },
        { "id" => "c2", "from" => "x", "to" => "e" }
      ]
      generator = described_class.new(flowchart_double(elements, connections))

      expect(generator.structure_errors).to include(
        "Element 'Unsafe\nKernel.raise(\"LABEL_INJECTION\")' uses unsupported structural type '#{type}'"
      )
      expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:unsupported_structural_element)
        expect(error.details).to include("x:#{type}")
      }
    end
  end
end
