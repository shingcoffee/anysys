# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::StructureValidator do
  # Convenience builder: returns a simple topological_order_provider that
  # performs Kahn's algorithm inline on the supplied elements/connections.
  # This lets StructureValidator tests remain DB-free while still exercising
  # the cycle-detection branch with a real topo-sort.
  def make_provider(elements, connections)
    lambda do
      graph_builder = ActivityGenerator::GraphBuilder.new(elements, connections)
      graph_builder.build.topological_order
    end
  end

  def build_element(id:, type:, label: nil)
    { "id" => id, "type" => type, "label" => label || type.capitalize }
  end

  def build_connection(from:, to:)
    { "from" => from, "to" => to }
  end

  # Errors from validating the per-describe `elements`/`connections` graph,
  # driven by a real Kahn topo-sort provider.
  let(:validator_options) { {} }

  subject(:errors) do
    described_class.new(
      elements,
      connections,
      topological_order_provider: make_provider(elements, connections),
      **validator_options
    ).call
  end

  # -----------------------------------------------------------------------
  # Valid graph — no errors expected
  # -----------------------------------------------------------------------
  describe "valid graph" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "p1", type: "process", label: "Do Work"),
        build_element(id: "e1", type: "end")
      ]
    end

    describe "unsupported structural elements" do
      let(:elements) do
        [
          build_element(id: "s1", type: "start"),
          build_element(id: "x1", type: "transaction", label: "Unsupported transaction"),
          build_element(id: "e1", type: "end")
        ]
      end
      let(:connections) do
        [
          build_connection(from: "s1", to: "x1"),
          build_connection(from: "x1", to: "e1")
        ]
      end

      it "rejects removed structural element types explicitly" do
        expect(errors).to include(
          "Element 'Unsupported transaction' uses unsupported structural type 'transaction'"
        )
      end
    end

    describe "end topology" do
      let(:elements) do
        [
          build_element(id: "s1", type: "start"),
          build_element(id: "e1", type: "end"),
          build_element(id: "p1", type: "process", label: "After end")
        ]
      end

      describe "decision topology" do
        let(:elements) do
          [
            build_element(id: "s1", type: "start"),
            build_element(id: "d1", type: "decision", label: "Route"),
            build_element(id: "e1", type: "end")
          ]
        end
        let(:connections) do
          [
            build_connection(from: "s1", to: "d1"),
            build_connection(from: "d1", to: "e1")
          ]
        end

        it "requires at least two outgoing branch connections" do
          expect(errors).to include("Decision element 'Route' requires at least two outgoing connections")
        end
      end
      let(:connections) do
        [
          build_connection(from: "s1", to: "e1"),
          build_connection(from: "e1", to: "p1")
        ]
      end

      it "rejects outgoing connections from terminal End elements" do
        expect(errors).to include("End element 'End' must not have outgoing connections")
      end
    end

    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "p1", to: "e1")
      ]
    end

    it "returns an empty error array for a well-formed graph" do
      expect(errors).to be_empty
    end
  end

  # -----------------------------------------------------------------------
  # Missing Start
  # -----------------------------------------------------------------------
  describe "missing start element" do
    let(:elements) do
      [
        build_element(id: "p1", type: "process", label: "Do Work"),
        build_element(id: "e1", type: "end")
      ]
    end

    let(:connections) { [build_connection(from: "p1", to: "e1")] }

    it "reports a Missing Start error" do
      expect(errors).to include("Missing Start element")
    end
  end

  # -----------------------------------------------------------------------
  # Multiple Starts
  # -----------------------------------------------------------------------
  describe "multiple start elements" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start", label: "Start A"),
        build_element(id: "s2", type: "start", label: "Start B"),
        build_element(id: "p1", type: "process", label: "Work"),
        build_element(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "s2", to: "p1"),
        build_connection(from: "p1", to: "e1")
      ]
    end

    it "reports a Multiple Start elements error" do
      expect(errors).to include("Multiple Start elements")
    end
  end

  # -----------------------------------------------------------------------
  # Missing End
  # -----------------------------------------------------------------------
  describe "missing end element" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "p1", type: "process", label: "Work")
      ]
    end

    let(:connections) { [build_connection(from: "s1", to: "p1")] }

    it "reports a Missing End error" do
      expect(errors).to include("Missing End element")
    end
  end

  # -----------------------------------------------------------------------
  # Dangling connections (unknown from/to ids)
  # -----------------------------------------------------------------------
  describe "dangling connections" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_connection(from: "s1", to: "GHOST"),
        build_connection(from: "MISSING", to: "e1")
      ]
    end

    it "reports an error for a connection whose 'to' id does not exist" do
      expect(errors).to include("Connection to unknown element id 'GHOST'")
    end

    it "reports an error for a connection whose 'from' id does not exist" do
      expect(errors).to include("Connection from unknown element id 'MISSING'")
    end
  end

  # -----------------------------------------------------------------------
  # Element with no incoming connection (unreachable / dangling node)
  # -----------------------------------------------------------------------
  describe "element with no incoming connections" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "p1", type: "process", label: "Orphan"),
        build_element(id: "e1", type: "end")
      ]
    end

    # p1 has no connection pointing to it
    let(:connections) do
      [
        build_connection(from: "s1", to: "e1")
      ]
    end

    it "reports that the orphan element has no incoming connections" do
      expect(errors).to include("Element 'Orphan' has no incoming connections")
    end
  end

  # -----------------------------------------------------------------------
  # Unreachable from start (has incoming edge but is disconnected from start path)
  # -----------------------------------------------------------------------
  describe "node unreachable from Start" do
    # p2 has an incoming edge (from p_island to p2) but p_island is itself not
    # reachable from start, so p2 is also unreachable.
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "p1", type: "process", label: "Reachable"),
        build_element(id: "p_island", type: "process", label: "Island"),
        build_element(id: "p2", type: "process", label: "Also Island"),
        build_element(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "p1", to: "e1"),
        build_connection(from: "p_island", to: "p2"),  # island sub-graph
        build_connection(from: "p2", to: "p_island")   # back-edge in island (cycle)
      ]
    end

    it "reports unreachable elements that are not reachable from Start" do
      # Cycle nodes also appear in the unreachable list — we only care that
      # the unreachable error is present.
      expect(errors.any? { |e| e.include?("not reachable from Start") }).to be true
    end
  end

  # -----------------------------------------------------------------------
  # Cycle detection
  # -----------------------------------------------------------------------
  describe "cycle detection" do
    # Graph: start -> p1 -> p2 -> p1 (cycle) -> end (unreachable due to cycle)
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "p1", type: "process", label: "Step A"),
        build_element(id: "p2", type: "process", label: "Step B"),
        build_element(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "p1", to: "p2"),
        build_connection(from: "p2", to: "p1"),  # back-edge creates cycle
        build_connection(from: "p2", to: "e1")
      ]
    end

    it "reports a cycle involving the cyclic element ids" do
      cycle_error = errors.find { |e| e.include?("Cycle detected") }
      expect(cycle_error).to be_present
      expect(cycle_error).to include("p1").or include("p2")
    end
  end

  # -----------------------------------------------------------------------
  # Multiple errors accumulate
  # -----------------------------------------------------------------------
  describe "multiple validation errors" do
    let(:elements) { [] }
    let(:connections) { [] }

    it "accumulates both Missing Start and Missing End when graph is empty" do
      expect(errors).to include("Missing Start element")
      expect(errors).to include("Missing End element")
    end
  end

  # -----------------------------------------------------------------------
  # Class-name collision with a targeted sub-flow (B5)
  # -----------------------------------------------------------------------
  describe "class name collision with a subflow" do
    let(:parent) { instance_double("Flowchart", id: 11, name: "enrol student") }
    let(:child) { instance_double("Flowchart", id: 22, name: "Enrol Student") }
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        {
          "id" => "sf1",
          "type" => "subflow",
          "label" => "Child flow",
          "properties" => { "flowchartId" => child.id }
        },
        build_element(id: "e1", type: "end")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "sf1"),
        build_connection(from: "sf1", to: "e1")
      ]
    end
    let(:validator_options) do
      {
        flowchart: parent,
        subflow_lookup: ->(id) { id.to_s == child.id.to_s ? child : nil }
      }
    end

    it "reports class_name_collision when the parent class name equals a sub-flow's" do
      expect(errors).to include(
        I18n.t("maint_core.flowcharts.structure_errors.class_name_collision", name: "EnrolStudentActivity")
      )
    end

    it "uses the zh-CN class_name_collision wording" do
      I18n.with_locale(:"zh-CN") do
        expect(errors).to include(
          I18n.t("maint_core.flowcharts.structure_errors.class_name_collision", name: "EnrolStudentActivity", locale: :"zh-CN")
        )
      end
    end

    context "when the targeted sub-flow derives a different class name" do
      let(:child) { instance_double("Flowchart", id: 22, name: "validate user") }

      it "does not report class_name_collision" do
        expect(errors.grep(/collides with a sub-flow/)).to be_empty
      end
    end

    context "when flowchart is given without subflow_lookup" do
      let(:validator_options) { { flowchart: parent } }

      it "does not run the collision check and does not query Flowchart" do
        expect(Flowchart).not_to receive(:find_by)
        expect(errors.grep(/collides with a sub-flow/)).to be_empty
      end
    end

    context "when the lookup returns nil" do
      let(:validator_options) do
        { flowchart: parent, subflow_lookup: ->(_id) { nil } }
      end

      it "does not report class_name_collision for an inaccessible or cross-tenant subflow" do
        expect(errors.grep(/collides with a sub-flow/)).to be_empty
      end
    end
  end

  describe "sibling subflow class name collision" do
    let(:parent) { instance_double("Flowchart", id: 11, name: "Parent Flow") }
    let(:helper) { instance_double("Flowchart", id: 22, name: "Helper") }
    let(:helper_lc) { instance_double("Flowchart", id: 33, name: "helper") }
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        {
          "id" => "sf1",
          "type" => "subflow",
          "label" => "First",
          "properties" => { "flowchartId" => helper.id }
        },
        {
          "id" => "sf2",
          "type" => "subflow",
          "label" => "Second",
          "properties" => { "flowchartId" => helper_lc.id }
        },
        build_element(id: "e1", type: "end")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "sf1"),
        build_connection(from: "sf1", to: "sf2"),
        build_connection(from: "sf2", to: "e1")
      ]
    end
    let(:validator_options) do
      {
        flowchart: parent,
        subflow_lookup: ->(id) {
          { helper.id.to_s => helper, helper_lc.id.to_s => helper_lc }[id.to_s]
        }
      }
    end

    it "reports class_name_collision when two distinct children derive the same class name" do
      expect(errors).to include(
        I18n.t("maint_core.flowcharts.structure_errors.class_name_collision", name: "HelperActivity")
      )
    end

    context "when both subflows reference the same child flowchart" do
      let(:elements) do
        [
          build_element(id: "s1", type: "start"),
          {
            "id" => "sf1",
            "type" => "subflow",
            "label" => "First",
            "properties" => { "flowchartId" => helper.id }
          },
          {
            "id" => "sf2",
            "type" => "subflow",
            "label" => "Second",
            "properties" => { "flowchartId" => helper.id }
          },
          build_element(id: "e1", type: "end")
        ]
      end
      let(:validator_options) do
        { flowchart: parent, subflow_lookup: ->(id) { id.to_s == helper.id.to_s ? helper : nil } }
      end

      it "does not report class_name_collision" do
        expect(errors.grep(/collides with a sub-flow/)).to be_empty
      end
    end
  end

  # -----------------------------------------------------------------------
  # One action per process (D1)
  # -----------------------------------------------------------------------
  describe "process with multiple actions" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        {
          "id" => "p1",
          "type" => "process",
          "label" => "Create",
          "properties" => {
            "steps" => [
              { "action" => "new_model" },
              { "action" => "save_model" }
            ]
          }
        },
        build_element(id: "e1", type: "end")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "p1", to: "e1")
      ]
    end

    it "reports process_multiple_actions" do
      expect(errors).to include(
        I18n.t("maint_core.flowcharts.structure_errors.process_multiple_actions", label: "Create")
      )
    end

    it "uses the zh-CN process_multiple_actions wording" do
      I18n.with_locale(:"zh-CN") do
        expect(errors).to include(
          I18n.t("maint_core.flowcharts.structure_errors.process_multiple_actions", label: "Create")
        )
      end
    end
  end

  # -----------------------------------------------------------------------
  # Error message shape — returns Array<String>
  # -----------------------------------------------------------------------
  describe "multiple outgoing connections" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "p1", type: "process", label: "Do Work"),
        build_element(id: "e1", type: "end"),
        build_element(id: "e2", type: "end", label: "Other End")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "p1", to: "e1"),
        build_connection(from: "p1", to: "e2")
      ]
    end

    it "reports multiple_outgoing naming the process" do
      expect(errors).to include(
        I18n.t("maint_core.flowcharts.structure_errors.multiple_outgoing", label: "Do Work")
      )
    end

    it "uses the zh-CN multiple_outgoing wording" do
      I18n.with_locale(:"zh-CN") do
        expect(errors).to include(
          I18n.t("maint_core.flowcharts.structure_errors.multiple_outgoing", label: "Do Work")
        )
      end
    end
  end

  describe "Start with two outgoing connections" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start", label: "Start"),
        build_element(id: "p1", type: "process", label: "A"),
        build_element(id: "p2", type: "process", label: "B"),
        build_element(id: "e1", type: "end")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "p1"),
        build_connection(from: "s1", to: "p2"),
        build_connection(from: "p1", to: "e1"),
        build_connection(from: "p2", to: "e1")
      ]
    end

    it "rejects Start the same way as any non-Decision/Loop element" do
      expect(errors).to include(
        I18n.t("maint_core.flowcharts.structure_errors.multiple_outgoing", label: "Start")
      )
    end
  end

  describe "Decision and Loop are exempt from multiple_outgoing" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "d1", type: "decision", label: "Route"),
        build_element(id: "loop1", type: "loop", label: "Repeat"),
        build_element(id: "p1", type: "process", label: "Body"),
        build_element(id: "e1", type: "end")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "d1"),
        build_connection(from: "d1", to: "loop1"),
        build_connection(from: "d1", to: "e1"),
        build_connection(from: "loop1", to: "p1"),
        build_connection(from: "loop1", to: "e1"),
        build_connection(from: "p1", to: "loop1")
      ]
    end

    it "does not report multiple_outgoing for Decision or Loop" do
      expect(errors.grep(/at most one outgoing/)).to be_empty
    end
  end

  describe "timer element" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "t1", type: "timer", label: "Wait"),
        build_element(id: "e1", type: "end")
      ]
    end
    let(:connections) do
      [
        build_connection(from: "s1", to: "t1"),
        build_connection(from: "t1", to: "e1")
      ]
    end

    it "reports the unsupported type message" do
      expect(errors).to include(
        I18n.t("maint_core.flowcharts.structure_errors.unsupported_type", label: "Wait", type: "timer")
      )
    end
  end

  describe "return type" do
    let(:elements) do
      [
        build_element(id: "s1", type: "start"),
        build_element(id: "e1", type: "end")
      ]
    end

    let(:connections) { [build_connection(from: "s1", to: "e1")] }

    it "returns an Array" do
      expect(errors).to be_a(Array)
    end

    context "when the graph is invalid" do
      let(:elements) { [build_element(id: "p1", type: "process", label: "Work")] }
      let(:connections) { [] }

      it "contains only strings when errors are present" do
        expect(errors).to all(be_a(String))
      end
    end
  end
end
