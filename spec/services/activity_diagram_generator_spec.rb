# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityDiagramGenerator do
  let(:entity) { create(:entity) }

  def el(id, type, label, properties = {})
    { "id" => id, "type" => type, "label" => label, "x" => 100, "y" => 50, "width" => 100, "height" => 45,
      "properties" => properties }
  end

  def conn(id, from, to, extra = {})
    { "id" => id, "from" => from, "to" => to }.merge(extra)
  end

  def assign(var)
    { "steps" => [{ "action" => "assign_value",
      "config" => { "resultVar" => var, "valueType" => "string", "stringValue" => "taken" } }] }
  end

  def condition(left, operator, right = "")
    { "type" => "group", "joins" => [],
      "conditions" => [{ "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }] }
  end

  def decision(id, label, left = "ctx.params.amount")
    el(id, "decision", label, "routeBy" => "condition", "condition" => condition(left, ">", "100"))
  end

  def build(elements, connections, **attrs)
    configuration = { "elements" => elements, "connections" => connections, "metadata" => { "canvas" => {} } }
    create(:flowchart, **attrs, configuration: configuration.to_json)
  end

  def node(label)
    graph.nodes.find { |candidate| candidate.label == label } || raise("no node labelled #{label}")
  end

  def edges_between(from, to)
    graph.edges.select { |edge| edge.from == node(from).id && edge.to == node(to).id }
  end

  subject(:graph) { described_class.new(target_flowchart).graph }

  let(:diagram) { graph.to_mermaid }

  context "with a linear flowchart" do
    let(:target_flowchart) { create(:flowchart, :simple) }

    it "draws Start, each step and the End element top-down" do
      expect(diagram).to start_with("flowchart TD")
      expect(graph.nodes.map(&:kind)).to eq(%i[start step end failure])
      expect(node("Begin").kind).to eq(:start)
      expect(diagram).to match(/^  n_start\(\["Begin"\]\)$/)
      expect(diagram.scan("-->").size).to eq(2)
    end

    it "styles each kind with its own class" do
      expect(diagram).to include("classDef startNode", "classDef stepNode", "classDef endNode")
      expect(diagram).to match(/^  class n_start startNode$/)
    end

    it "hides collect_errors and the failure track by default" do
      expect(diagram).not_to include("collect_errors", I18n.t("flowchart_elements.trace.collect_errors"), "-.->")
      expect(diagram).not_to include(I18n.t("flowchart_elements.trace.failure"))
    end

    it "draws one Failure terminal reached by every step when failure paths are on" do
      expect(graph.failure_paths?).to be(true)
      with_failures = graph.to_mermaid(failure_paths: true)
      expect(with_failures).to match(/^  n_failure\(\["#{I18n.t('flowchart_elements.trace.failure')}"\]\)$/)
      expect(with_failures.scan("-.-> n_failure").size).to eq(1)
      expect(with_failures).to match(/^  linkStyle \d+ stroke:#f87171/)
    end

    it "lists the legend kinds without the failure terminal" do
      expect(graph.kinds).to eq(%i[start step end])
    end

    it "is exposed as Mermaid source through #generate" do
      expect(described_class.new(target_flowchart).generate).to eq(diagram)
      expect(described_class.new(target_flowchart).generate(failure_paths: true)).to include("-.->")
    end
  end

  context "with no activity code" do
    let(:target_flowchart) { create(:flowchart, :empty).tap { |flowchart| flowchart.update_column(:activity, nil) } }

    it "returns nil" do
      expect(graph).to be_nil
      expect(described_class.new(target_flowchart).generate).to be_nil
    end
  end

  context "with invalid activity code" do
    let(:target_flowchart) { create(:flowchart, :simple).tap { |flowchart| flowchart.update_column(:activity, "invalid ruby code") } }

    it "returns nil and logs the error" do
      expect(AppLogger).to receive(:error).with(/Failed to build activity class/, source: "ActivityDiagramGenerator")
      expect(graph).to be_nil
    end
  end

  context "with a decision" do
    let(:target_flowchart) do
      build(
        [el("s1", "start", "Start"), decision("d1", "Check amount"), el("a1", "process", "High value", assign("high")),
          el("b1", "process", "Low value", assign("low")), el("e1", "end", "Finish")],
        [conn("c1", "s1", "d1"), conn("c2", "d1", "a1", "label" => "Over 100", "matchValue" => "true"),
          conn("c3", "d1", "b1", "matchValue" => "false"), conn("c4", "a1", "e1"), conn("c5", "b1", "e1")]
      )
    end

    it "draws the decision as a rhombus" do
      expect(node("Check amount").kind).to eq(:decision)
      expect(diagram).to include(%({"Check amount"}))
    end

    it "labels each branch with its connection label, else the editor's match label" do
      expect(edges_between("Check amount", "High value").map(&:label)).to eq(["Over 100"])
      expect(edges_between("Check amount", "Low value").map(&:label))
        .to eq([I18n.t("maint_core.flowcharts.editor.property_editor.no_match_label")])
      expect(diagram).to include(%(-->|"Over 100"|), %(-->|"No"|))
    end

    it "translates fallback branch labels" do
      zh = I18n.with_locale(:"zh-CN") { described_class.new(target_flowchart).generate }
      expect(zh).to include(%(-->|"#{I18n.t('maint_core.flowcharts.editor.property_editor.no_match_label', locale: :"zh-CN")}"|))
    end

    it "merges both branches into the one End element" do
      expect(edges_between("High value", "Finish").size).to eq(1)
      expect(edges_between("Low value", "Finish").size).to eq(1)
      expect(graph.nodes.count { |candidate| candidate.kind == :end }).to eq(1)
    end

    it "never draws the default railway outputs of a router" do
      expect(diagram).not_to match(/\|"(success|failure)"\|/i)
    end
  end

  context "with branches ending at different End elements" do
    let(:target_flowchart) do
      build(
        [el("s1", "start", "Start"), decision("d1", "Big order"), el("a1", "process", "Review", assign("r")),
          el("e1", "end", "Approved"), el("e2", "end", "Rejected")],
        [conn("c1", "s1", "d1"), conn("c2", "d1", "a1", "matchValue" => "true"),
          conn("c3", "d1", "e2", "matchValue" => "false"), conn("c4", "a1", "e1")]
      )
    end

    it "draws each End element as its own terminal" do
      expect(edges_between("Review", "Approved").size).to eq(1)
      expect(edges_between("Big order", "Rejected").map(&:label))
        .to eq([I18n.t("maint_core.flowcharts.editor.property_editor.no_match_label")])
      expect(diagram).to include(%(e_e1(["Approved"])), %(e_e2(["Rejected"])))
    end
  end

  context "with a loop" do
    let(:exit_label) { "All done" }
    let(:target_flowchart) do
      build(
        [el("s1", "start", "Start"),
          el("l1", "loop", "Each item", "loopType" => "for_each", "collection" => "items", "maxIterations" => 10),
          el("w1", "process", "Work", assign("w")), el("a1", "process", "After", assign("a")), el("e1", "end", "End")],
        [conn("c1", "s1", "l1"), conn("c2", "l1", "w1"), conn("c3", "w1", "l1"),
          conn("c4", "l1", "a1", "label" => exit_label), conn("c5", "a1", "e1")]
      )
    end

    it "draws the loop as a hexagon with its body, back edge and exit" do
      expect(node("Each item").kind).to eq(:loop)
      expect(diagram).to include(%({{"Each item"}}))
      expect(edges_between("Each item", "Work").map(&:label)).to eq([I18n.t("maint_core.flowcharts.show.diagram.loop_repeat")])
      expect(edges_between("Work", "Each item").map(&:label)).to eq([nil])
      expect(edges_between("Each item", "After").map(&:label)).to eq(["All done"])
    end

    context "when the exit has no label" do
      let(:exit_label) { "" }

      it "labels it Done" do
        expect(edges_between("Each item", "After").map(&:label)).to eq([I18n.t("common.actions.done")])
      end
    end
  end

  context "with subflow elements" do
    let(:child) { create(:flowchart, :simple, name: "Shared Child", customer: entity.customer) }
    let(:subflow) { { "flowchartId" => child.id, "inputs" => [{ "value" => "ctx" }], "outputs" => [{ "value" => "ctx" }] } }
    let(:target_flowchart) do
      build(
        [el("s1", "start", "Start"), el("sf1", "subflow", "First Check", subflow), el("sf2", "subflow", "Second Check", subflow),
          el("e1", "end", "End")],
        [conn("c1", "s1", "sf1"), conn("c2", "sf1", "sf2"), conn("c3", "sf2", "e1")],
        customer: entity.customer
      )
    end

    it "draws each reference as its own subroutine node" do
      expect(node("First Check").kind).to eq(:subflow)
      expect(node("Second Check").kind).to eq(:subflow)
      expect(node("First Check").id).not_to eq(node("Second Check").id)
      expect(diagram).to include(%([["First Check"]]), %([["Second Check"]]))
      expect(diagram).to match(/^  class \S+,\S+ subflowNode$/)
    end
  end

  context "with an End that writes a response" do
    let(:target_flowchart) do
      build(
        [el("s1", "start", "Start"), decision("d1", "Is vip", "ctx.params.vip"),
          el("e_fast", "end", "Fast Exit", "responseType" => "value", "returnValue" => "ctx.params.marker"),
          el("p1", "process", "Standard Path", assign("standard")), el("e_std", "end", "Standard End")],
        [conn("c1", "s1", "d1"), conn("c2", "d1", "e_fast", "label" => "Yes", "matchValue" => "true"),
          conn("c3", "d1", "p1", "matchValue" => "false"), conn("c4", "p1", "e_std")]
      )
    end

    it "draws the responding End once, as a terminal with no edge onward" do
      fast_exit = node("Fast Exit")
      expect(fast_exit.kind).to eq(:end)
      expect(diagram.scan("Fast Exit").size).to eq(1)
      expect(diagram).to match(/^  #{fast_exit.id}\(\["Fast Exit"\]\)$/)
      expect(graph.edges.select { |edge| edge.from == fast_exit.id && !edge.failure }).to be_empty
    end

    it "still draws the response-less End reached by the other branch" do
      expect(edges_between("Standard Path", "Standard End").size).to eq(1)
      expect(diagram).not_to include(I18n.t("flowchart_elements.trace.success"))
    end
  end

  context "with hostile labels" do
    let(:hostile) { "Hello\r\nworld] \"pipe| --> %%{init: {}}%% 中文; #35; `tick` <img src=x>" }
    let(:target_flowchart) do
      build(
        [el("s1", "start", "Start"), decision("d1", hostile), el("a1", "process", "High", assign("h")),
          el("b1", "process", "Low", assign("l")), el("e1", "end", "Finish")],
        [conn("c1", "s1", "d1"), conn("c2", "d1", "a1", "label" => hostile, "matchValue" => "true"),
          conn("c3", "d1", "b1", "matchValue" => "false"), conn("c4", "a1", "e1"), conn("c5", "b1", "e1")]
      )
    end

    it "keeps every label on one line inside a quoted, entity-escaped Mermaid string" do
      node_label = diagram[/\{"(Hello[^"]*)"\}/, 1]
      edge_label = diagram[/-->\|"(Hello[^"]*)"\|/, 1]

      [node_label, edge_label].each do |label|
        expect(label).to start_with("Hello world] #quot;pipe#124; --#gt; #37;#37;{init: {}}#37;#37; 中文; #35;35; #96;tick#96;")
        expect(label).not_to match(/[\r\n"|%<>`]/)
        expect(label.gsub(/#\w+;/, "")).not_to include("#")
      end
    end

    it "truncates long labels" do
      label = "A" * 80
      renderer = ActivityDiagramGenerator::MermaidRenderer.new(
        [ActivityDiagramGenerator::Graph::Node.new(id: "s_a", kind: :step, label: label)], []
      )
      expect(renderer.render).to include(%(s_a("#{'A' * 59}…")))
    end

    it "encodes backslashes" do
      renderer = ActivityDiagramGenerator::MermaidRenderer.new(
        [ActivityDiagramGenerator::Graph::Node.new(id: "s_a", kind: :step, label: %(a\\"b))], []
      )
      expect(renderer.render).to include(%(s_a("a#92;#quot;b")))
    end

    it "strips bidi controls" do
      renderer = ActivityDiagramGenerator::MermaidRenderer.new(
        [ActivityDiagramGenerator::Graph::Node.new(id: "s_a", kind: :step, label: "ab\u202Ecd\u2066")], []
      )
      expect(renderer.render).to include(%(s_a("ab cd")))
    end
  end
end
