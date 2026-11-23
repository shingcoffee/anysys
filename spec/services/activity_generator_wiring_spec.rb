# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "Railway wiring" do
  def compile(elements, edges, name: "Wiring Sample", id: 14, children: {})
    flowchart = instance_double(
      Flowchart,
      id: id,
      name: name,
      customer_id: 1,
      shared?: false,
      customer_owned?: true,
      elements: elements,
      connections: edges.each_with_index.map { |edge, index|
        { "id" => edge[3] || "c#{index}", "from" => edge[0], "to" => edge[1], "matchValue" => edge[2], "label" => edge[4] }
      }
    )
    namespace = Module.new
    children.each do |child_id, activity|
      child = instance_double(Flowchart, id: child_id, name: "Child#{child_id}", shared?: true, elements: [])
      allow(Flowchart).to receive(:find_by).with(id: child_id).and_return(child)
      namespace.const_set("Child#{child_id}Activity", activity)
    end
    code = described_class.new(flowchart).generate
    expect(code).to be_present, "expected generated code, got #{code.inspect}"
    namespace.module_eval(code)
    [namespace.const_get(activity_const(name)), code]
  end

  def activity_const(name)
    ActivityGenerator::NameDeriver.new.derive_activity_class_name(name).to_sym
  end

  def element(id, type, properties = {}, label: id)
    properties = { "responseType" => "none" }.merge(properties) if type == "end" && properties["responseType"].nil?
    { "id" => id, "label" => label, "type" => type, "properties" => properties }
  end

  def boolean_decision(left)
    {
      "routeBy" => "condition",
      "condition" => {
        "type" => "group",
        "joins" => [],
        "conditions" => [{ "kind" => "field", "leftOperand" => left, "operator" => "is_true", "rightOperand" => "" }]
      }
    }
  end

  def value_decision(left)
    subject = left.to_s.start_with?("ctx.") ? "ctx[:#{left.to_s.delete_prefix('ctx.')}]" : left
    { "routeBy" => "value", "subject" => subject }
  end

  def circuit_pairs(klass)
    nodes = klass.to_h[:nodes]
    klass.to_h[:circuit].to_h[:map].flat_map do |from, outs|
      outs.map do |signal, to|
        [nodes[from][:id], signal_semantic(signal), nodes[to][:id]]
      end
    end
  end

  def signal_semantic(signal)
    hash = signal.respond_to?(:to_h) ? signal.to_h : {}
    return hash[:semantic] if hash[:semantic]
    return :success if signal == Trailblazer::Activity::Right
    return :failure if signal == Trailblazer::Activity::Left

    inspect = signal.inspect
    return :success if inspect.include?("Right")
    return :failure if inspect.include?("Left")

    hash[:semantic] || inspect
  end

  def expected_circuit(klass, elements, edges)
    step_by_element = klass::CANVAS[:steps].invert
    stepless = elements.select { |item| item["type"] == "end" && (item.dig("properties", "responseType").presence || "none") == "none" }
      .to_set { |item| item["id"] }
    routes = klass::CANVAS[:routes] || {}
    loop_steps = routes.select { |_id, map| map.keys == [:done] }.keys.map(&:to_sym).to_set
    decisions = routes.keys.map(&:to_sym).to_set - loop_steps

    canvas = edges.filter_map do |from, to|
      from_el = elements.find { |item| item["id"] == from }
      next if from_el && from_el["type"] == "end" && stepless.include?(from)

      from_id = from_el && from_el["type"] == "start" ? "Start.default" : step_by_element[from]&.to_sym
      to_id = stepless.include?(to) ? "End.success" : step_by_element[to]&.to_sym
      next unless from_id && to_id

      [from_id, to_id]
    end

    elements.each do |item|
      next unless item["type"] == "end"
      next if stepless.include?(item["id"])

      step_id = step_by_element[item["id"]]&.to_sym
      canvas << [step_id, "End.success"] if step_id
    end

    steps = klass::CANVAS[:steps].keys
    failures = steps.map { |id| [id, :collect_errors] }
    failures << [:collect_errors, "End.failure"]

    expected = (canvas + failures).uniq
    pairs = circuit_pairs(klass)
    leaks = pairs.select { |from, semantic, to|
      decisions.include?(from.to_sym) && semantic == :success && to != :collect_errors
    }
    expect(leaks).to eq([]), "decision :success leaked to a canvas step: #{leaks.inspect}"

    actual = pairs.map { |from, _semantic, to| [from, to] }.uniq
    [expected, actual]
  end

  def assert_circuit(klass, elements, edges)
    expected, actual = expected_circuit(klass, elements, edges)
    expect(actual).to match_array(expected)
  end

  def call(activity, ctx = {})
    signal, (result, _) = activity.call([ctx, {}])
    [signal.to_h[:semantic], result]
  end

  describe "circuit equality" do
    it "matches a linear chain" do
      elements = [element("s", "start"), element("a", "process", {}, label: "A"),
        element("b", "process", {}, label: "B"), element("e", "end")]
      edges = [["s", "a"], ["a", "b"], ["b", "e"]]
      klass, _code = compile(elements, edges, name: "Linear")
      assert_circuit(klass, elements, edges)
    end

    it "matches a decision with both branches to a merge" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.big"), label: "Is Large Order"),
        element("p1", "process", {}, label: "Manual Review"),
        element("p2", "process", {}, label: "Auto Approve"),
        element("p3", "process", {}, label: "Finalize"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "p1", "true"], ["d1", "p2", "false"], ["p1", "p3"], ["p2", "p3"], ["p3", "e"]]
      klass, _code = compile(elements, edges, name: "Merge Decision")
      assert_circuit(klass, elements, edges)
    end

    it "matches nested decisions" do
      elements = [
        element("s", "start"),
        element("outer", "decision", boolean_decision("ctx.outer"), label: "Outer"),
        element("inner", "decision", boolean_decision("ctx.inner"), label: "Inner"),
        element("a", "process", {}, label: "A"),
        element("b", "process", {}, label: "B"),
        element("other", "process", {}, label: "Other"),
        element("e", "end")
      ]
      edges = [["s", "outer"], ["outer", "inner", "true"], ["outer", "other", "false"],
        ["inner", "a", "true"], ["inner", "b", "false"], ["a", "e"], ["b", "e"], ["other", "e"]]
      klass, _code = compile(elements, edges, name: "Nested")
      assert_circuit(klass, elements, edges)
    end

    it "matches a non-nested merge with a cross edge" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.selected"), label: "Route"),
        element("p3", "process", {}, label: "Cross"),
        element("p2", "process", {}, label: "Shared"),
        element("p4", "process", {}, label: "After"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "p2", "true"], ["d1", "p3", "false"], ["p3", "p2"], ["p2", "p4"], ["p4", "e"]]
      klass, _code = compile(elements, edges, name: "Cross Merge")
      assert_circuit(klass, elements, edges)
    end

    it "matches branches ending at two different Ends" do
      elements = [
        element("s", "start"),
        element("d1", "decision", value_decision("ctx.priority"), label: "Route"),
        element("high", "process", {}, label: "Handle High"),
        element("low", "process", {}, label: "Handle Low"),
        element("end_yes", "end"),
        element("end_no", "end")
      ]
      edges = [["s", "d1"], ["d1", "high", "high"], ["d1", "low", ""], ["high", "end_yes"], ["low", "end_no"]]
      klass, _code = compile(elements, edges, name: "Two Ends")
      assert_circuit(klass, elements, edges)
    end

    it "matches a decision branch straight to a stepless End" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.big"), label: "Is Large Order"),
        element("p1", "process", {}, label: "Auto Approve"),
        element("end_3", "end"),
        element("end_1", "end")
      ]
      edges = [["s", "d1"], ["d1", "end_3", "true"], ["d1", "p1", "false"], ["p1", "end_1"]]
      klass, _code = compile(elements, edges, name: "Straight End")
      assert_circuit(klass, elements, edges)
    end

    it "matches an empty branch straight to the merge node" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.ok"), label: "Route"),
        element("p1", "process", {}, label: "Work"),
        element("p2", "process", {}, label: "Merge"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "p1", "true"], ["d1", "p2", "false"], ["p1", "p2"], ["p2", "e"]]
      klass, _code = compile(elements, edges, name: "Empty Branch")
      assert_circuit(klass, elements, edges)
    end

    it "matches a subflow in a branch" do
      child = Class.new(Trailblazer::Activity::Railway) do
        step :work
        def work(ctx, **) = true
      end
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.selected"), label: "Route"),
        element("sf1", "subflow", { "flowchartId" => 1 }, label: "Child"),
        element("p1", "process", {}, label: "Other"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "sf1", "true"], ["d1", "p1", "false"], ["sf1", "e"], ["p1", "e"]]
      klass, _code = compile(elements, edges, name: "Subflow Branch", children: { 1 => child })
      assert_circuit(klass, elements, edges)
    end

    it "matches unequal-depth reconverge" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.selected"), label: "Split"),
        element("a", "process", {}, label: "A"),
        element("b", "process", {}, label: "B"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "a", "true"], ["d1", "b", "false"], ["a", "b"], ["b", "e"]]
      klass, _code = compile(elements, edges, name: "Unequal Depth")
      assert_circuit(klass, elements, edges)
    end

    it "matches a decision branch into another decision's branch region" do
      elements = [
        element("s", "start"),
        element("outer", "decision", boolean_decision("ctx.outer"), label: "Outer"),
        element("inner", "decision", boolean_decision("ctx.inner"), label: "Inner"),
        element("left", "process", {}, label: "Left"),
        element("right", "process", {}, label: "Right"),
        element("after", "process", {}, label: "After"),
        element("e", "end")
      ]
      edges = [
        ["s", "outer"], ["outer", "inner", "true"], ["outer", "after", "false"],
        ["inner", "left", "true"], ["inner", "right", "false"],
        ["left", "after"], ["right", "after"], ["after", "e"]
      ]
      klass, _code = compile(elements, edges, name: "Cross Decision")
      assert_circuit(klass, elements, edges)
    end

    it "matches a subflow at a merge" do
      child = Class.new(Trailblazer::Activity::Railway) do
        step :work
        def work(ctx, **) = true
      end
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.selected"), label: "Route"),
        element("p1", "process", {}, label: "Work"),
        element("sf1", "subflow", { "flowchartId" => 1 }, label: "Child"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "p1", "true"], ["d1", "sf1", "false"], ["p1", "sf1"], ["sf1", "e"]]
      klass, _code = compile(elements, edges, name: "Subflow Merge", children: { 1 => child })
      assert_circuit(klass, elements, edges)
    end

    it "matches two decisions in sequence" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.first"), label: "First"),
        element("p1", "process", {}, label: "Prep"),
        element("d2", "decision", boolean_decision("ctx.second"), label: "Second"),
        element("yes", "process", {}, label: "Yes Path"),
        element("no", "process", {}, label: "No Path"),
        element("e", "end")
      ]
      edges = [
        ["s", "d1"], ["d1", "p1", "true"], ["d1", "d2", "false"], ["p1", "d2"],
        ["d2", "yes", "true"], ["d2", "no", "false"], ["yes", "e"], ["no", "e"]
      ]
      klass, _code = compile(elements, edges, name: "Sequential Decisions")
      assert_circuit(klass, elements, edges)
    end

    it "matches a terminal non-End element in the middle of the declaration order" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.ok"), label: "Route"),
        element("reject", "process", {}, label: "Reject"),
        element("approve", "process", {}, label: "Approve"),
        element("end_1", "end"),
        element("end_2", "end")
      ]
      edges = [["s", "d1"], ["d1", "reject", "true"], ["d1", "approve", "false"], ["reject", "end_1"], ["approve", "end_2"]]
      klass, _code = compile(elements, edges, name: "Mid Terminal")
      assert_circuit(klass, elements, edges)
    end

    it "matches an End-with-response that is not last" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.ok"), label: "Route"),
        element("notify", "end", { "responseType" => "value", "returnValue" => "ctx.result" }, label: "Notify Team"),
        element("other", "process", {}, label: "Other"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "notify", "true"], ["d1", "other", "false"], ["other", "e"]]
      klass, _code = compile(elements, edges, name: "Response End Mid")
      assert_circuit(klass, elements, edges)
    end

    it "matches Start connected only to a stepless End" do
      elements = [element("s", "start"), element("e", "end")]
      edges = [["s", "e"]]
      klass, _code = compile(elements, edges, name: "Start End Only")
      assert_circuit(klass, elements, edges)
    end

    it "does not self-loop when an element id collides with another step name" do
      elements = [
        element("start_1", "start"),
        element("process_2", "process", {}, label: "处理"),
        element("process_1", "process", {}, label: "Prepare"),
        element("end_1", "end")
      ]
      edges = [["start_1", "process_2"], ["process_2", "process_1"], ["process_1", "end_1"]]
      klass, code = compile(elements, edges, name: "Collision")
      expect(code).to include("step :process_1")
      expect(code).to include("step :prepare")
      expect(code).not_to match(/step :process_1, Output\(:success\) => Id\(:process_1\)/)
      assert_circuit(klass, elements, edges)
      _status, ctx = call(klass)
      expect(ctx).to be_a(Hash)
    end

    it "matches a for_each loop including the back-edge" do
      elements = [
        element("s", "start"),
        element("init", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "total", "valueType" => "integer", "integerValue" => 0 } }] }, label: "Init Total"),
        element("loop", "loop", { "loopType" => "for_each", "collection" => "items", "itemVariable" => "item" }, label: "Each Item"),
        element("add", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "total", "valueType" => "expression", "valueExpression" => "ctx[:total].to_i + ctx[:item].to_i" } }] }, label: "Add Item"),
        element("report", "process", {}, label: "Report"),
        element("e", "end")
      ]
      edges = [["s", "init"], ["init", "loop"], ["loop", "add"], ["add", "loop"], ["loop", "report"], ["report", "e"]]
      klass, code = compile(elements, edges, name: "Sum Loop")
      expect(code).not_to include("LoopBody")
      expect(code).not_to include("step task:")
      expect(code).to include("Output(Routes::EachItem::Done, :done) => Id(:report)")
      expect(code).to include("Output(:success) => Id(:each_item)")
      assert_circuit(klass, elements, edges)
      status, ctx = call(klass, items: [1, 2, 3])
      expect(status).to eq(:success)
      expect(ctx[:_loop_iteration_count]).to eq(3)
    end
  end

  describe "taken-branch behaviour" do
    it "runs only the taken branch of an order-approval style graph" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.big"), label: "Is Large Order"),
        element("review", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "review", "valueType" => "string", "stringValue" => "1" } }] }, label: "Manual Review"),
        element("approve", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "approve", "valueType" => "string", "stringValue" => "1" } }] }, label: "Auto Approve"),
        element("final", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "final", "valueType" => "string", "stringValue" => "1" } }] }, label: "Finalize"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "review", "true"], ["d1", "approve", "false"], ["review", "final"], ["approve", "final"], ["final", "e"]]
      klass, _code = compile(elements, edges, name: "Order Approval")

      _status, yes = call(klass, big: true)
      expect(yes.values_at(:review, :approve, :final)).to eq(["1", nil, "1"])

      _status, no = call(klass, big: false)
      expect(no.values_at(:review, :approve, :final)).to eq([nil, "1", "1"])
    end

    it "fails through collect_errors when a decision returns the default success signal" do
      elements = [
        element("s", "start"),
        element("d1", "decision", boolean_decision("ctx.big"), label: "Is Large Order"),
        element("review", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "review", "valueType" => "string", "stringValue" => "1" } }] }, label: "Manual Review"),
        element("approve", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "approve", "valueType" => "string", "stringValue" => "1" } }] }, label: "Auto Approve"),
        element("final", "process", { "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "final", "valueType" => "string", "stringValue" => "1" } }] }, label: "Finalize"),
        element("e", "end")
      ]
      edges = [["s", "d1"], ["d1", "review", "true"], ["d1", "approve", "false"], ["review", "final"], ["approve", "final"], ["final", "e"]]
      klass, _code = compile(elements, edges, name: "Forced Right")
      klass.class_eval { def is_large_order(*) = Trailblazer::Activity::Right }

      status, ctx = call(klass, big: true)
      expect(status).to eq(:failure)
      expect(ctx.values_at(:review, :approve, :final)).to eq([nil, nil, nil])
    end
  end

  describe "flowchart 14 split-chain shape" do
    let(:entity) do
      create(:entity, name: "Student Profiles", property_schema: [
        { "name" => "Name", "name_slug" => "name", "type" => "String", "validators" => [{ "type" => "presence" }] }
      ].to_json)
    end

    def split_chain_elements
      [
        { "id" => "start_1", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "el_a", "type" => "process", "label" => "New Model", "properties" => { "steps" => [{ "action" => "new_model" }] } },
        { "id" => "el_b", "type" => "process", "label" => "Build Contract", "properties" => { "steps" => [{ "action" => "build_contract" }] } },
        { "id" => "el_c", "type" => "process", "label" => "Validate", "properties" => { "steps" => [{ "action" => "validate_contract" }] } },
        { "id" => "el_d", "type" => "process", "label" => "Save Model", "properties" => { "steps" => [{ "action" => "save_model" }] } },
        { "id" => "end_1", "type" => "end", "label" => "End", "properties" => {} }
      ]
    end

    def split_chain_connections
      [
        { "id" => "c1", "from" => "start_1", "to" => "el_a" },
        { "id" => "c2", "from" => "el_a", "to" => "el_b" },
        { "id" => "c3", "from" => "el_b", "to" => "el_c" },
        { "id" => "c4", "from" => "el_c", "to" => "el_d" },
        { "id" => "c5", "from" => "el_d", "to" => "end_1" }
      ]
    end

    def split_chain_flowchart
      instance_double(
        Flowchart,
        id: 14,
        name: "Create Student Profile",
        customer_id: entity.customer_id,
        shared?: false,
        customer_owned?: true,
        elements: split_chain_elements,
        connections: split_chain_connections
      )
    end

    it "emits one Railway step per box, CANVAS, and collect_errors" do
      flowchart = split_chain_flowchart
      code = described_class.new(flowchart, entity: entity).generate
      expect(code).to include('Generated from flowchart')
      expect(code).to include('Checked against entity: Student Profiles')
      expect(code).not_to include("Trigger:")
      expect(code).not_to include("Model class:")
      expect(code).not_to include("ctx[:_route_")
      expect(code).not_to include("return false unless ->")
      expect(code).to include("step :new_model")
      expect(code).to include("step :build_contract")
      expect(code).to include("step :validate")
      expect(code).to include("step :save_model")
      expect(code).to include("fail :collect_errors")
      expect(code).to include("CANVAS =")
      expect(code).to include('new_model: "el_a"')
      expect(code).to include('save_model: { success: "end_1" }')
      expect(code).to include("FlowchartRuntime::Errors.collect(ctx)")
      zh = I18n.with_locale(:"zh-CN") { described_class.new(flowchart, entity: entity).generate }
      expect(zh).to eq(code)
    end

    it "ends on failure with ctx[:errors] when a required attribute is blank" do
      flowchart = split_chain_flowchart
      code = described_class.new(flowchart).generate
      helper = Class.new { include ActivityClassBuilder }.new
      klass = helper.build_activity_class(code, entity: entity, flowchart: flowchart)
      expect(klass).to be_present
      signal, (ctx, _) = klass.call([{
        params: {},
        customer_id: entity.customer_id,
        bound_entity: entity,
        audience: :admin
      }, {}])
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(Array(ctx[:errors])).not_to be_empty
    end
  end

  describe "two-level decision sample" do
    it "generates Routes, merge wiring, and two End maps" do
      elements = [
        element("s", "start"),
        element("outer", "decision", boolean_decision("ctx.vip"), label: "Is Vip"),
        element("inner", "decision", boolean_decision("ctx.rush"), label: "Is Rush"),
        element("fast", "process", {}, label: "Fast Path"),
        element("slow", "process", {}, label: "Slow Path"),
        element("standard", "process", {}, label: "Standard Path"),
        element("end_ok", "end"),
        element("end_other", "end")
      ]
      edges = [
        ["s", "outer"],
        ["outer", "inner", "true"],
        ["outer", "standard", "false"],
        ["inner", "fast", "true"],
        ["inner", "slow", "false"],
        ["fast", "end_ok"],
        ["slow", "end_ok"],
        ["standard", "end_other"]
      ]
      klass, code = compile(elements, edges, name: "Two Level")
      assert_circuit(klass, elements, edges)
      expect(code).to include("module Routes")
      expect(code).to include("module IsVip")
      expect(code).to include("module IsRush")
      expect(code).to include("Output(Routes::IsVip::Yes, :yes)")
      expect(code).to include('ends:')
    end
  end
end
