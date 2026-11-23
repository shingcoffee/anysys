# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "loop region execution" do
  include LoopPhase4SpecHelpers

  def node(id, type, properties = {})
    properties = { "responseType" => "none" }.merge(properties) if type.to_s == "end" && properties["responseType"].nil?
    { "id" => id, "label" => id, "type" => type, "properties" => properties }
  end

  def cond_group(left, operator, right = "")
    LoopPhase4SpecHelpers.cond_group(left, operator, right)
  end

  def boolean_decision(left)
    LoopPhase4SpecHelpers.boolean_decision(left)
  end

  let(:properties) do
    {
      "loopType" => "while",
      "maxIterations" => 100,
      "condition" => cond_group("ctx._loop_iteration_count", "<", "3")
    }
  end
  let(:elements) do
    [node("start", "start"), node("repeat", "loop", properties),
      node("work", "process", "steps" => [{ "action" => "validate_contract", "config" => {} }]),
      node("after", "process", "steps" => [{ "action" => "save_model", "config" => {} }]), node("end", "end")]
  end
  # Deliberately put the exit edge before the body edge: order is not semantics.
  let(:edges) { [["start", "repeat"], ["repeat", "after"], ["repeat", "work"], ["work", "repeat"], ["after", "end"]] }
  let(:flowchart) do
    instance_double(Flowchart, id: 901, name: "Loop Execution", customer_id: 1, shared?: false, customer_owned?: true, elements: elements,
      connections: edges.each_with_index.map { |edge, i| { "id" => i.to_s, "from" => edge[0], "to" => edge[1], "matchValue" => edge[2] } })
  end
  let(:generator) { described_class.new(flowchart) }

  def run(ctx = {}, &iteration)
    namespace = Module.new
    code = generator.generate
    expect(code).to be_present
    namespace.module_eval(code)
    ctx[:count] ||= 0
    ctx[:visited] ||= []
    ctx[:model] ||= Object.new
    ctx[:contract] ||= double.tap do |contract|
      allow(contract).to receive(:validate) do
        ctx[:count] += 1
        ctx[:visited] << [ctx[:item], ctx[:index]]
        iteration ? iteration.call(ctx) : true
      end
      allow(contract).to receive(:sync)
      allow(contract).to receive(:save)
      allow(contract).to receive(:model).and_return(ctx[:model])
    end
    allow(FlowchartRuntime::Entries).to receive(:save) do |_ctx, _model|
      ctx[:after_count] = (ctx[:after_count] || 0) + 1
      true
    end
    signal, (result, _) = namespace.const_get(:LoopExecutionActivity).call([ctx, {}])
    [signal.to_h[:semantic], result]
  end

  [
    ["while", { "loopType" => "while", "maxIterations" => 100,
      "condition" => LoopPhase4SpecHelpers.cond_group("ctx._loop_iteration_count", "<", "3") }],
    ["runOnceFirst", { "loopType" => "while", "runOnceFirst" => true, "maxIterations" => 100,
      "condition" => LoopPhase4SpecHelpers.cond_group("ctx._loop_iteration_count", "<", "3") }],
    ["for_each", { "loopType" => "for_each", "collection" => "items", "maxIterations" => 100 }]
  ].each do |mode, props|
    context mode do
      let(:properties) { props }

      it "executes the complete body three times and the continuation once" do
        status, ctx = run(items: [10, 20, 30])
        expect(status).to eq(:success)
        expect(ctx.values_at(:count, :after_count, :_loop_iteration_count)).to eq([3, 1, 3])
        expect(ctx[:visited]).to eq([[10, 0], [20, 1], [30, 2]]) if mode == "for_each"
      end

      it "propagates body failure and skips later iterations and the exit" do
        status, ctx = run(items: [10, 20, 30]) { |state| state[:count] < 2 }
        expect(status).to eq(:failure)
        expect(ctx[:count]).to eq(2)
        expect(ctx).not_to have_key(:after_count)
      end

      it "honors a stopWhen condition without failing the Railway" do
        properties["stopWhen"] = cond_group("ctx.count", ">=", "2")
        status, ctx = run(items: [10, 20, 30])
        expect(status).to eq(:success)
        expect(ctx.values_at(:count, :after_count)).to eq([2, 1])
      end

      it "skips a body action when a Decision routes around it" do
        elements.insert(-2, node("route", "decision", boolean_decision("ctx.skip_work")), node("skipped", "process"))
        edges.delete(["repeat", "work"])
        edges.concat([["repeat", "route"], ["route", "work", "true"], ["route", "skipped", "false"], ["skipped", "repeat"]])
        status, ctx = run(items: [10, 20, 30], skip_work: false)
        expect(status).to eq(:success)
        expect(ctx.values_at(:count, :after_count)).to eq([0, 1])
      end
    end
  end

  [
    ["while", false],
    ["runOnceFirst", true]
  ].each do |mode, run_once|
    context "#{mode} condition" do
      let(:properties) do
        { "loopType" => "while", "runOnceFirst" => run_once, "maxIterations" => 10,
          "condition" => cond_group("ctx.count", "<", "2") }
      end

      it "re-evaluates the condition after body mutations" do
        status, ctx = run
        expect(status).to eq(:success)
        expect(ctx.values_at(:count, :after_count)).to eq([2, 1])
      end

      it "#{mode == 'while' ? 'skips' : 'executes'} the body when initially false" do
        status, ctx = run(count: 10)
        expect(status).to eq(:success)
        expect(ctx[:count]).to eq(run_once ? 11 : 10)
        expect(ctx[:after_count]).to eq(1)
      end
    end
  end

  context "for_each" do
    let(:properties) { { "loopType" => "for_each", "collection" => "items", "maxIterations" => 100 } }

    [nil, []].each do |items|
      it "skips the body for #{items.inspect}" do
        status, ctx = run(items: items)
        expect(status).to eq(:success)
        expect(ctx.values_at(:count, :after_count)).to eq([0, 1])
      end
    end

    it "binds each item before skip/break and counts skipped items toward the bound" do
      properties.merge!(
        "skipWhen" => cond_group("ctx.item", "is_empty"),
        "collectInto" => "collected"
      )
      status, ctx = run(items: [nil, 2, nil, 4])
      expect(status).to eq(:success)
      expect(ctx[:visited]).to eq([[2, 1], [4, 3]])
      expect(ctx[:collected]).to eq([2, 4])
      expect(ctx[:_loop_iteration_count]).to eq(2)
    end

    it "exposes custom item/index names to the body and local skip expressions" do
      properties.merge!(
        "itemVariable" => "entry",
        "indexVariable" => "position",
        "skipWhen" => cond_group("ctx.entry", "is_empty")
      )
      status, ctx = run(items: [nil, "a", "b"], pairs: []) do |state|
        state[:pairs] << [state[:entry], state[:position]]
        true
      end
      expect(status).to eq(:success)
      expect(ctx[:pairs]).to eq([["a", 1], ["b", 2]])
    end
  end

  it "resets per-invocation counters even when context is reused" do
    _, ctx = run
    status, ctx = run(ctx)
    expect(status).to eq(:success)
    expect(ctx.values_at(:count, :after_count, :_loop_iteration_count)).to eq([6, 2, 3])
  end

  it "keeps every body element in the generated CANVAS steps" do
    namespace = Module.new
    code = generator.generate
    expect(code).to be_present
    expect(code).not_to include("LoopBody")
    expect(code).not_to include("step task:")
    expect(code).not_to include("loop.io.initialize")
    expect(code).not_to include("ActivityGenerator::")
    expect(code).not_to match(/\b[0-9a-f]{64}\b/)
    expect(code).not_to include("loop do")
    expect(code).to include("Output(Routes::Repeat::Done, :done)")
    expect(code).to include("Output(:success) => Id(:repeat)")
    namespace.module_eval(code)
    canvas = namespace.const_get(:LoopExecutionActivity)::CANVAS
    expect(canvas[:steps].values).to include("repeat", "work", "after")
    expect(canvas[:routes][:repeat][:done]).to be_present
  end

  it "rejects itemVariable names that shadow header locals" do
    properties.replace("loopType" => "for_each", "collection" => "items", "itemVariable" => "state")
    expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
      expect(error.code).to eq(:invalid_generator_config)
      expect(error.details.join).to include("itemVariable")
      expect(error.details.join).to include("state")
    }
  end

  it "executes an empty-body header-to-End loop inside the header" do
    elements.replace([node("start", "start"), node("repeat", "loop", "loopType" => "while", "maxIterations" => 100,
      "condition" => cond_group("ctx._loop_iteration_count", "<", "4")), node("end", "end")])
    edges.replace([["start", "repeat"], ["repeat", "end"]])
    namespace = Module.new
    code = generator.generate
    expect(code).to be_present
    expect(code).to include("loop do")
    expect(code).to include("Output(:success) => Track(:failure)")
    expect(code).to include("Output(Routes::Repeat::Done, :done)")
    expect(code).not_to include("return true")
    expect(code).not_to include("LoopBody")
    namespace.module_eval(code)
    ctx = {}
    signal, (result, _) = namespace.const_get(:LoopExecutionActivity).call([ctx, {}])
    expect(signal.to_h[:semantic]).to eq(:success)
    expect(result[:_loop_iteration_count]).to eq(4)
    expect(result).not_to have_key(:_repeat)

    config = {
      "elements" => elements,
      "connections" => edges.each_with_index.map { |edge, i|
        { "id" => i.to_s, "from" => edge[0], "to" => edge[1], "matchValue" => edge[2] }
      },
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
    }
    record = create(:flowchart, name: "Empty Body Loop", configuration: config.to_json)
    record.update_column(:activity, described_class.new(record).generate)
    traced = ActivityTracer.new(record).call({})
    expect(traced.error).to be_nil
    expect(traced.trace_nodes.map { |node| node[:id] }).to eq([
      "Start.default",
      "repeat",
      "End.success"
    ])
  end

  it "traces the header and body once per for_each item" do
    properties.replace("loopType" => "for_each", "collection" => "items", "itemVariable" => "item", "maxIterations" => 10)
    elements.find { |element| element["id"] == "work" }["properties"]["steps"] = []
    elements.find { |element| element["id"] == "after" }["properties"]["steps"] = []
    config = {
      "elements" => elements,
      "connections" => edges.each_with_index.map { |edge, i|
        { "id" => i.to_s, "from" => edge[0], "to" => edge[1], "matchValue" => edge[2] }
      },
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
    }
    record = create(:flowchart, name: "Loop Trace", configuration: config.to_json)
    code = described_class.new(record).generate
    expect(code).to be_present
    record.update_column(:activity, code)
    result = ActivityTracer.new(record).call(items: [10, 20, 30])
    expect(result.error).to be_nil
    expect(result.success?).to eq(true)
    ids = result.trace_nodes.map { |node| node[:id] }
    expect(ids).to eq([
      "Start.default",
      "repeat", "work",
      "repeat", "work",
      "repeat", "work",
      "repeat",
      "after",
      "End.success"
    ])
  end

  it "runs sequential loops with independent iteration bounds" do
    elements.insert(-2, node("second", "loop", "loopType" => "while", "maxIterations" => 100,
      "condition" => cond_group("ctx._loop_iteration_count", "<", "2")),
      node("second_work", "process", "steps" => [{ "action" => "validate_contract", "config" => {} }]))
    edges.delete(["repeat", "after"])
    edges.concat([["repeat", "second"], ["second", "second_work"], ["second_work", "second"], ["second", "after"]])
    status, ctx = run
    expect(status).to eq(:success)
    expect(ctx.values_at(:count, :after_count)).to eq([5, 1])
    counters = ctx.select { |key, _| key.to_s.start_with?("_loop_iteration_count") }
    expect(counters).to eq(_loop_iteration_count: 2)
  end

  it "short-circuits actions within a loop body before advancing the loop" do
    work = elements.find { |element| element["id"] == "work" }
    work["properties"]["steps"] << { "action" => "save_model", "config" => {} }
    split = FlowchartDefinitions::ProcessSplitter.call(
      "elements" => elements,
      "connections" => edges.each_with_index.map { |edge, i|
        { "id" => i.to_s, "from" => edge[0], "to" => edge[1], "matchValue" => edge[2] }
      }
    )
    elements.replace(split["elements"])
    edges.replace(split["connections"].map { |c| [c["from"], c["to"], c["matchValue"]] })
    status, ctx = run { false }
    expect(status).to eq(:failure)
    expect(ctx[:count]).to eq(1)
    expect(ctx).not_to have_key(:after_count)
  end

  it "does not wrap repeated actions with leftover step-level retry or timeout keys" do
    work = elements.find { |element| element["id"] == "work" }
    work["properties"]["steps"][0].merge!("retryCount" => 1, "timeout" => 2)
    expect(generator.generate).not_to include("Timeout.timeout")
    expect(generator.generate).not_to include("retry_count")
    status, ctx = run
    expect(status).to eq(:success)
    expect(ctx.values_at(:count, :after_count)).to eq([3, 1])
  end

  it "re-evaluates a Decision in the body on every iteration" do
    elements.insert(-2, node("route", "decision", "routeBy" => "condition",
      "condition" => cond_group("ctx._loop_iteration_count", "<", "3")), node("skipped", "process"))
    edges.delete(["repeat", "work"])
    edges.concat([["repeat", "route"], ["route", "work", "true"], ["route", "skipped", "false"], ["skipped", "repeat"]])
    status, ctx = run
    expect(status).to eq(:success)
    expect(ctx.values_at(:count, :after_count)).to eq([2, 1])
  end

  [true, false].each do |selected|
    it "honors an enclosing Decision selecting the loop: #{selected}" do
      elements.insert(1, node("route", "decision", boolean_decision("ctx.selected")))
      edges.delete(["start", "repeat"])
      edges.concat([["start", "route"], ["route", "repeat", "true"], ["route", "after", "false"]])
      status, ctx = run(selected: selected)
      expect(status).to eq(:success)
      expect(ctx.values_at(:count, :after_count)).to eq([selected ? 3 : 0, 1])
    end
  end

  it "executes a subflow within the loop body with circuit flow options intact" do
    child = instance_double(Flowchart, id: 1, name: "Loop Child", shared?: true, elements: [])
    allow(Flowchart).to receive(:find_by).with(id: 1).and_return(child)
    stub_const("LoopChildActivity", Class.new(Trailblazer::Activity::Railway) do
      step task: ->((ctx, options), **) {
        ctx[:child_visits] = (ctx[:child_visits] || 0) + 1
        [Trailblazer::Activity::Right, [ctx, options]]
      }
    end)
    elements.insert(-2, node("child", "subflow", "flowchartId" => 1))
    edges.delete(["work", "repeat"])
    edges.concat([["work", "child"], ["child", "repeat"]])
    status, ctx = run
    expect(status).to eq(:success)
    expect(ctx.values_at(:count, :child_visits, :after_count)).to eq([3, 3, 1])
  end

  it "rejects malformed nested conditions with an element-scoped validation error" do
    properties["condition"] = { "type" => "group", "conditions" => [{ "type" => "group", "conditions" => [nil] }] }
    expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
      expect(error.code).to eq(:invalid_generator_config)
      expect(error.element_id).to eq("repeat")
      expect(error.details.map { |detail| [detail.field, detail.code] }).to include(["condition", :nested_group])
    }
  end

  it "rejects a shortcut from the loop body to the exit" do
    edges << ["work", "after"]
    expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
      expect(error.code).to eq(:invalid_loop_topology)
      expect(error.details).to include(:loop_body_escape)
    }
  end

  it "rejects entering the middle of a loop from outside" do
    edges << ["start", "work"]
    expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
      expect(error.details).to include(:loop_body_external_entry)
    }
  end

  it "still rejects cycles that do not close at a loop header" do
    edges << ["work", "work"]
    expect(generator.structure_errors.join).to include("Cycle detected")
    expect(generator.generate).to be_nil
  end

  it "rejects a downstream body without a closing backedge rather than executing it once" do
    edges.delete(["repeat", "after"])
    edges.delete(["work", "repeat"])
    edges << ["work", "after"]
    expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
      expect(error.details).to include(:loop_requires_body_and_exit)
    }
    expect(generator.structure_errors.join).to include("Loop requires one body path and one exit")
    expect(generator.structure_errors.join).not_to include("loop_requires_body_and_exit")
    I18n.with_locale(:"zh-CN") do
      expect(generator.structure_errors.join).to include("循环必须同时具有一条循环体路径和一条退出路径")
    end
  end

  it "rejects nested loop regions explicitly" do
    elements.insert(-2, node("inner", "loop", "loopType" => "while", "maxIterations" => 2,
      "condition" => cond_group("ctx.go", "is_true")), node("inner_work", "process"))
    edges.delete(["repeat", "work"])
    edges.concat([["repeat", "inner"], ["inner", "inner_work"], ["inner_work", "inner"], ["inner", "work"]])
    expect { generator.generate }.to raise_error(ActivityGenerator::Error) { |error|
      expect(error.details).to include(:nested_loop)
    }
  end
end
