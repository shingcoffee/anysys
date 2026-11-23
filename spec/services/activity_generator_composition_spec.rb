# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "composed Railway execution" do
  def element(id, type, properties = {})
    { "id" => id, "label" => id, "type" => type, "properties" => properties }
  end

  def yes_no(left)
    {
      "routeBy" => "condition",
      "condition" => {
        "type" => "group", "joins" => [],
        "conditions" => [{ "kind" => "field", "leftOperand" => left, "operator" => "is_true", "rightOperand" => "" }]
      }
    }
  end

  def compile(elements, edges, children: {})
    flowchart = instance_double(Flowchart, id: 900, name: "Composition", customer_id: 1, shared?: false, customer_owned?: true, elements: elements,
      connections: edges.each_with_index.map { |edge, i| { "id" => i.to_s, "from" => edge[0], "to" => edge[1], "matchValue" => edge[2] } })
    namespace = Module.new
    children.each do |id, activity|
      child = instance_double(Flowchart, id: id, name: "Child#{id}", shared?: true, elements: [])
      allow(Flowchart).to receive(:find_by).with(id: id).and_return(child)
      namespace.const_set("Child#{id}Activity", activity)
    end
    code = described_class.new(flowchart).generate
    expect(code).to be_present
    namespace.module_eval(code)
    namespace.const_get(:CompositionActivity)
  end

  def process_chain(*steps)
    split = FlowchartDefinitions::ProcessSplitter.call(
      "elements" => [
        element("start", "start"),
        element("work", "process", "steps" => steps),
        element("end", "end")
      ],
      "connections" => [
        { "id" => "0", "from" => "start", "to" => "work" },
        { "id" => "1", "from" => "work", "to" => "end" }
      ]
    )
    [split["elements"], split["connections"].map { |c| [c["from"], c["to"], c["matchValue"]] }]
  end

  def action(name, **options)
    { "action" => name, "config" => {} }.merge(options.stringify_keys)
  end

  def call(activity, ctx = {})
    signal, (result, _) = activity.call([ctx, {}])
    [signal.to_h[:semantic], result]
  end

  it "stops validate then save on a false first action" do
    activity = compile(*process_chain(action("validate_contract"), action("save_model")))
    contract = double(validate: false)
    expect(contract).not_to receive(:sync)
    expect(FlowchartRuntime::Entries).not_to receive(:save)
    expect(call(activity, contract: contract, params: {})[0]).to eq(:failure)
  end

  it "runs save after successful validation and propagates its failure" do
    activity = compile(*process_chain(action("validate_contract"), action("save_model")))
    model = double
    contract = double(model: model)
    expect(contract).to receive(:validate).with({}).ordered.and_return(true)
    expect(FlowchartRuntime::Entries).to receive(:save).with(anything, contract).ordered.and_return(false)
    expect(call(activity, contract: contract, params: {}, model: model)[0]).to eq(:failure)
  end

  it "does not wrap an action with leftover step-level guard, retry, or timeout keys" do
    activity = compile(*process_chain(
      action("validate_contract", guardCondition: "ctx[:validate]", retryCount: 1, timeout: 2),
      action("save_model")
    ))
    model = double
    contract = double(model: model)
    expect(contract).to receive(:validate).and_return(true)
    expect(FlowchartRuntime::Entries).to receive(:save).with(anything, contract).and_return(true)
    expect(Timeout).not_to receive(:timeout)
    expect(call(activity, contract: contract, validate: false, model: model)[0]).to eq(:success)
  end

  it "does not retry a false return or execute the following action" do
    activity = compile(*process_chain(action("validate_contract", retryCount: 3), action("save_model")))
    contract = double
    expect(contract).to receive(:validate).once.and_return(false)
    expect(contract).not_to receive(:sync)
    expect(FlowchartRuntime::Entries).not_to receive(:save)
    expect(call(activity, contract: contract)[0]).to eq(:failure)
  end

  it "preserves parent decision routing after a child runs" do
    child = Class.new(Trailblazer::Activity::Railway) do
      step ->(ctx, **) { ctx[:child_ran] = true }
    end
    elements = [element("start", "start"), element("route", "decision", yes_no("ctx.selected")), element("child", "subflow", "flowchartId" => 1),
      element("selected_work", "process", "steps" => [action("validate_contract")]),
      element("other", "process", "steps" => [action("save_model")]), element("end", "end")]
    activity = compile(elements, [["start", "route"], ["route", "child", "true"], ["route", "other", "false"],
      ["child", "selected_work"], ["selected_work", "end"], ["other", "end"]], children: { 1 => child })
    contract = double
    expect(contract).to receive(:validate).once.and_return(true)
    expect(contract).not_to receive(:sync)
    expect(FlowchartRuntime::Entries).not_to receive(:save)
    expect(call(activity, selected: true, contract: contract)[0]).to eq(:success)
  end

  it "allows repeated references to the same child and passes flow options through" do
    child = Class.new(Trailblazer::Activity::Railway) do
      step task: ->((ctx, flow_options), **) {
        flow_options[:calls] << ctx[:token]
        [Trailblazer::Activity::Right, [ctx, flow_options]]
      }
    end
    activity = compile([element("start", "start"), element("first", "subflow", "flowchartId" => 1),
      element("second", "subflow", "flowchartId" => 1), element("end", "end")],
      [["start", "first"], ["first", "second"], ["second", "end"]], children: { 1 => child })
    options = { calls: [] }
    signal, (_, result_options) = activity.call([{ token: :shared }, options])
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(result_options[:calls]).to eq([:shared, :shared])
  end

  [true, false].each do |selected|
    it "only invokes the selected subflow branch when the decision is #{selected}" do
      child = Class.new(Trailblazer::Activity::Railway) do
        step ->(ctx, **) { ctx[:calls] << :child; ctx[:child_success] }
      end
      elements = [element("start", "start"), element("route", "decision", yes_no("ctx.selected")), element("child", "subflow", "flowchartId" => 1), element("other", "process"), element("end", "end")]
      activity = compile(elements, [["start", "route"], ["route", "child", "true"],
        ["route", "other", "false"], ["child", "end"], ["other", "end"]], children: { 1 => child })
      status, ctx = call(activity, selected: selected, calls: [], child_success: false)
      expect(status).to eq(selected ? :failure : :success)
      expect(ctx[:calls]).to eq(selected ? [:child] : [])
    end
  end

  [[false, true], [true, false], [true, true]].each do |outer, inner|
    it "enforces both enclosing decision guards for a subflow (#{outer}, #{inner})" do
      child = Class.new(Trailblazer::Activity::Railway) do
        step ->(ctx, **) { ctx[:called] = true }
      end
      elements = [element("start", "start"), element("outer", "decision", yes_no("ctx.outer")),
        element("inner", "decision", yes_no("ctx.inner")), element("child", "subflow", "flowchartId" => 1), element("end", "end")]
      activity = compile(elements, [["start", "outer"], ["outer", "inner", "true"], ["outer", "end", "false"],
        ["inner", "child", "true"], ["inner", "end", "false"], ["child", "end"]], children: { 1 => child })
      status, ctx = call(activity, outer: outer, inner: inner)
      expect(status).to eq(:success)
      expect(!!ctx[:called]).to eq(outer && inner)
    end
  end
end
