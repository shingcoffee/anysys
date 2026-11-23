# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "merge data flow (B1/B2)" do
  def element(id, type, properties = {}, label: id)
    properties = { "responseType" => "none" }.merge(properties) if type == "end" && properties["responseType"].nil?
    { "id" => id, "label" => label, "type" => type, "properties" => properties }
  end

  def yes_no_decision(left, operator: "is_true", right: "")
    {
      "routeBy" => "condition",
      "condition" => {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }
        ]
      }
    }
  end

  def value_route_decision(subject)
    { "routeBy" => "value", "subject" => subject }
  end

  def assign(id, pin, value)
    element(id, "process", { "steps" => [{
      "id" => id,
      "action" => "assign_value",
      "config" => { "resultVar" => pin, "valueType" => "string", "stringValue" => value }
    }] })
  end

  def compile(name, elements, edges)
    flowchart = instance_double(
      Flowchart,
      id: 901,
      name: name,
      customer_id: 1,
      shared?: false,
      customer_owned?: true,
      elements: elements,
      connections: edges.each_with_index.map { |edge, i|
        { "id" => "c#{i}", "from" => edge[0], "to" => edge[1], "matchValue" => edge[2] }
      }
    )
    code = described_class.new(flowchart).generate
    expect(code).to be_present
    namespace = Module.new
    namespace.module_eval(code)
    class_name = ActivityGenerator::NameDeriver.new.derive_activity_class_name(name)
    [code, namespace.const_get(class_name)]
  end

  def call(klass, ctx = {})
    _signal, (result, _) = klass.call([ctx, {}])
    result
  end

  # Order Approval: status is seeded before the decision and overwritten on the
  # approved branch; reviewer is written on two exclusive review branches.
  def order_approval
    elements = [
      element("start", "start"),
      assign("set_pending", "status", "pending"),
      element("is_approved", "decision", yes_no_decision("ctx.approved")),
      assign("set_approved", "status", "approved"),
      element("is_manager", "decision", yes_no_decision("ctx.manager")),
      assign("set_manager", "reviewer", "manager"),
      assign("set_team", "reviewer", "team"),
      element("merge", "process", { "steps" => [{
        "id" => "summarize",
        "action" => "template_render",
        "config" => {
          "template" => "{{status}}/{{reviewer}}",
          "resultVar" => "summary",
          "variables" => [{ "key" => "status", "value" => "status" }, { "key" => "reviewer", "value" => "reviewer" }]
        }
      }] }, label: "Merge"),
      element("end", "end")
    ]
    edges = [
      %w[start set_pending],
      %w[set_pending is_approved],
      ["is_approved", "set_approved", "true"],
      ["is_approved", "is_manager", "false"],
      ["is_manager", "set_manager", "true"],
      ["is_manager", "set_team", "false"],
      %w[set_approved merge],
      %w[set_manager merge],
      %w[set_team merge],
      %w[merge end]
    ]
    compile("Order Approval", elements, edges)
  end

  describe "order-approval sample" do
    let!(:compiled) { order_approval }
    let(:code) { compiled[0] }
    let(:klass) { compiled[1] }

    it "reads pending/manager when the manager review branch runs" do
      expect(call(klass, approved: false, manager: true)[:summary]).to eq("pending/manager")
    end

    it "reads pending/team when the team review branch runs" do
      expect(call(klass, approved: false, manager: false)[:summary]).to eq("pending/team")
    end

    it "reads approved/ when status is overwritten on the approved branch" do
      expect(call(klass, approved: true)[:summary]).to eq("approved/")
    end
  end

  def summarize(id, pin, target = "summary")
    element(id, "process", { "steps" => [{
      "id" => id,
        "action" => "assign_value",
        "config" => {
          "valueType" => "ctx_ref",
          "ctxRefVariable" => pin,
          "resultVar" => target
        }
    }] })
  end

  def with_output_rename(el, pin, renamed_to)
    el["properties"]["io_overrides"] = {
      "outputs" => [{ "pin" => pin, "renamed_to" => renamed_to }]
    }
    el
  end

  it "lets a self-writer read the upstream value before its own write" do
    elements = [
      element("start", "start"),
      element("seed", "process", { "steps" => [{
        "id" => "seed",
        "action" => "assign_value",
        "config" => { "resultVar" => "count", "valueType" => "integer", "integerValue" => 10 }
      }] }),
      element("bump", "process", { "steps" => [{
        "id" => "bump",
        "action" => "assign_value",
        "config" => { "resultVar" => "count", "valueType" => "expression", "valueExpression" => "ctx[:count].to_i + 1" }
      }] }),
      element("observe", "process", { "steps" => [{
        "id" => "observe",
        "action" => "assign_value",
        "config" => { "resultVar" => "observed", "valueType" => "ctx_ref", "ctxRefVariable" => "count" }
      }] }),
      element("end", "end")
    ]
    edges = [%w[start seed], %w[seed bump], %w[bump observe], %w[observe end]]
    _code, klass = compile("Self Read", elements, edges)
    result = call(klass)
    expect(result[:observed]).to eq(11)
    expect(result[:count]).to eq(10)
  end

  it "reads an author-renamed linear overwrite instead of the conflict suffix" do
    overwrite = with_output_rename(assign("overwrite", "v", "over"), "v", "author_v")
    elements = [
      element("start", "start"),
      assign("seed", "v", "seed"),
      overwrite,
      summarize("merge", "v"),
      element("end", "end")
    ]
    _code, klass = compile("Author Linear", elements, [
      %w[start seed], %w[seed overwrite], %w[overwrite merge], %w[merge end]
    ])
    result = call(klass)
    expect(result[:summary]).to eq("over")
    expect(result[:author_v]).to eq("over")
    expect(result[:v]).to eq("seed")
  end

  it "reads author-renamed exclusive writers on both branches" do
    left = with_output_rename(assign("left", "v", "L"), "v", "left_v")
    right = with_output_rename(assign("right", "v", "R"), "v", "right_v")
    elements = [
      element("start", "start"),
      element("route", "decision", yes_no_decision("ctx.left")),
      left,
      right,
      summarize("merge", "v"),
      element("end", "end")
    ]
    edges = [
      %w[start route],
      ["route", "left", "true"],
      ["route", "right", "false"],
      %w[left merge],
      %w[right merge],
      %w[merge end]
    ]
    _code, klass = compile("Author Exclusive", elements, edges)
    expect(call(klass, left: true)[:summary]).to eq("L")
    expect(call(klass, left: false)[:summary]).to eq("R")
  end

  describe "decision leftOperand ctx.v after a pre-write and one-branch overwrite" do
    def ctx_v_route
      elements = [
        element("start", "start"),
        assign("seed", "v", "seed"),
        element("take_over", "decision", yes_no_decision("ctx.take_over")),
        assign("overwrite", "v", "over"),
        element("route", "decision", yes_no_decision("ctx.v", operator: "==", right: "over")),
        assign("taken", "path", "over"),
        assign("skipped", "path", "seed"),
        element("end", "end", { "responseType" => "value", "returnValue" => "ctx.v" })
      ]
      edges = [
        %w[start seed],
        %w[seed take_over],
        ["take_over", "overwrite", "true"],
        ["take_over", "route", "false"],
        %w[overwrite route],
        ["route", "taken", "true"],
        ["route", "skipped", "false"],
        %w[taken end],
        %w[skipped end]
      ]
      compile("Ctx Dig Route", elements, edges)
    end

    let!(:compiled) { ctx_v_route }
    let(:code) { compiled[0] }
    let(:klass) { compiled[1] }

    it "routes through the overwrite path when ctx.v was overwritten" do
      result = call(klass, take_over: true)
      expect(result[:path]).to eq("over")
      expect(result[:response]).to eq("over")
    end

    it "routes through the seed path when the overwrite branch is skipped" do
      result = call(klass, take_over: false)
      expect(result[:path]).to eq("seed")
      expect(result[:response]).to eq("seed")
    end
  end

  it "reads exclusive diamond writers that share the original pin" do
    elements = [
      element("start", "start"),
      element("route", "decision", yes_no_decision("ctx.left")),
      assign("left", "v", "L"),
      assign("right", "v", "R"),
      summarize("merge", "v"),
      element("end", "end")
    ]
    _code, klass = compile("Diamond", elements, [
      %w[start route],
      ["route", "left", "true"],
      ["route", "right", "false"],
      %w[left merge],
      %w[right merge],
      %w[merge end]
    ])
    expect(call(klass, left: true)[:summary]).to eq("L")
    expect(call(klass, left: false)[:summary]).to eq("R")
  end

  it "reads a three-way merge when one branch is silent" do
    elements = [
      element("start", "start"),
      assign("seed", "v", "seed"),
      element("choice", "decision", value_route_decision("ctx[:choice]")),
      assign("write_a", "v", "A"),
      assign("write_b", "v", "B"),
      summarize("merge", "v"),
      element("end", "end")
    ]
    _code, klass = compile("Silent Branch", elements, [
      %w[start seed],
      %w[seed choice],
      ["choice", "write_a", "a"],
      ["choice", "write_b", "b"],
      ["choice", "merge", "c"],
      %w[write_a merge],
      %w[write_b merge],
      %w[merge end]
    ])
    expect(call(klass, choice: "a")[:summary]).to eq("A")
    expect(call(klass, choice: "b")[:summary]).to eq("B")
    expect(call(klass, choice: "c")[:summary]).to eq("seed")
  end

  it "reads the innermost nested writer that actually ran" do
    elements = [
      element("start", "start"),
      assign("seed", "v", "s"),
      element("outer", "decision", yes_no_decision("ctx.outer")),
      assign("mid", "v", "m"),
      element("inner", "decision", yes_no_decision("ctx.inner")),
      assign("leaf", "v", "i"),
      summarize("merge", "v"),
      element("end", "end")
    ]
    _code, klass = compile("Nested Writers", elements, [
      %w[start seed],
      %w[seed outer],
      ["outer", "mid", "true"],
      ["outer", "merge", "false"],
      %w[mid inner],
      ["inner", "leaf", "true"],
      ["inner", "merge", "false"],
      %w[leaf merge],
      %w[merge end]
    ])
    expect(call(klass, outer: false)[:summary]).to eq("s")
    expect(call(klass, outer: true, inner: false)[:summary]).to eq("m")
    expect(call(klass, outer: true, inner: true)[:summary]).to eq("i")
  end

  it "reads each merge independently after a second decision" do
    elements = [
      element("start", "start"),
      assign("seed", "v", "s"),
      element("first", "decision", yes_no_decision("ctx.first")),
      assign("a", "v", "A"),
      assign("b", "v", "B"),
      summarize("merge_one", "v", "first_seen"),
      element("second", "decision", yes_no_decision("ctx.second")),
      assign("c", "v", "C"),
      summarize("merge_two", "v", "second_seen"),
      element("end", "end")
    ]
    _code, klass = compile("Merge Then Merge", elements, [
      %w[start seed],
      %w[seed first],
      ["first", "a", "true"],
      ["first", "b", "false"],
      %w[a merge_one],
      %w[b merge_one],
      %w[merge_one second],
      ["second", "c", "true"],
      ["second", "merge_two", "false"],
      %w[c merge_two],
      %w[merge_two end]
    ])
    expect(call(klass, first: true, second: true)).to include(first_seen: "A", second_seen: "C")
    expect(call(klass, first: true, second: false)).to include(first_seen: "A", second_seen: "A")
    expect(call(klass, first: false, second: true)).to include(first_seen: "B", second_seen: "C")
    expect(call(klass, first: false, second: false)).to include(first_seen: "B", second_seen: "B")
  end

  it "compiles a Chinese format_string template that reads a merged renamed pin on both paths" do
    elements = [
      element("start", "start"),
      assign("seed", "v", "seed"),
      element("take_over", "decision", yes_no_decision("ctx.take_over")),
      assign("overwrite", "v", "over"),
      element("merge", "process", { "steps" => [{
        "id" => "summarize",
        "action" => "template_render",
        "config" => {
          "template" => "结果{{v}}",
          "resultVar" => "summary",
          "variables" => [{ "key" => "v", "value" => "v" }]
        }
      }] }),
      element("end", "end")
    ]
    code, klass = compile("Chinese Merge", elements, [
      %w[start seed],
      %w[seed take_over],
      ["take_over", "overwrite", "true"],
      ["take_over", "merge", "false"],
      %w[overwrite merge],
      %w[merge end]
    ])
    expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
    expect(call(klass, take_over: true)[:summary]).to eq("结果over")
    expect(call(klass, take_over: false)[:summary]).to eq("结果seed")
  end

  it "still writes the conflict-resolver key when the author renamed_to is unsafe" do
    overwrite = with_output_rename(assign("overwrite", "v", "over"), "v", "1bad")
    elements = [
      element("start", "start"),
      assign("seed", "v", "seed"),
      overwrite,
      summarize("merge", "v"),
      element("end", "end")
    ]
    _code, klass = compile("Unsafe Author", elements, [
      %w[start seed], %w[seed overwrite], %w[overwrite merge], %w[merge end]
    ])
    result = call(klass)
    expect(result[:summary]).to eq("over")
    expect(result[:v]).to eq("seed")
  end

  it "emits Entries.query(ctx) so bound_entity and customer_id stay on the runtime ctx" do
    query = element("p1", "process", { "steps" => [{
      "id" => "query", "action" => "query_models",
      "config" => {
        "resultVar" => "values",
        "select" => %w[name email],
        "returns" => "values",
        "distinct" => false,
        "orderBy" => "created_at"
      }
    }] })

    code, = compile("Scope After Query", [
      element("start", "start"), assign("a1", "marker", "x"), query, element("end", "end")
    ], [%w[start a1], %w[a1 p1], %w[p1 end]])

    expect(code).to match(/FlowchartRuntime::Entries\.query\(\s*ctx,/)
    expect(code).not_to include("Entries.query(ctx[")
  end
end
