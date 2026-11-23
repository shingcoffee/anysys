# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator, "loop validation and execution" do
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

  def value_decision(subject)
    LoopPhase4SpecHelpers.value_decision(subject)
  end

  def action(id, name, config)
    { "id" => id, "action" => name, "config" => config }
  end

  def assignment(id, key, value)
    node(id, "process", "steps" => [action(id, "assign_value", "resultVar" => key, "valueType" => "string", "stringValue" => value)])
  end

  def configuration(elements, edges)
    { "elements" => elements, "connections" => edges.each_with_index.map { |(from, to, match), index|
      { "id" => "edge_#{index}", "from" => from, "to" => to, "matchValue" => match }
    } }
  end

  def flowchart(config)
    Flowchart.new(name: "Loop Review", configuration: config.to_json)
  end

  def execute(config, ctx = {})
    record = flowchart(config)
    expect(FlowchartServerValidator.new(record, config).call).to eq([])
    io = FlowchartInputOutputValidator.call(record)
    expect(io.errors).to eq([])
    namespace = Module.new
    namespace.module_eval(described_class.new(record).generate)
    signal, (result, _) = namespace.const_get(:LoopReviewActivity).call([ctx, {}])
    expect(signal.to_h[:semantic]).to eq(:success)
    result
  end

  def dataflow_config(iterations: 1)
    elements = [node("start", "start"), assignment("seed", "value", "seed"), node("gap", "process"),
      node("loop", "loop", "loopType" => "while", "maxIterations" => 100,
        "condition" => cond_group("ctx._loop_iteration_count", "<", iterations.to_s)),
      node("reader", "process", "steps" => [
        action("read", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "observed", "template" => "{{value}}")
      ]),
      node("remember", "process", "steps" => [
        action("remember", "assign_value", "resultVar" => "history", "valueType" => "expression", "valueExpression" => "Array(ctx[:history]) + [ctx[:observed]]")
      ]), assignment("writer", "value", "body"), node("end", "end")]
    configuration(elements, [["start", "seed"], ["seed", "gap"], ["gap", "loop"], ["loop", "reader"],
      ["reader", "remember"], ["remember", "writer"], ["writer", "loop"], ["loop", "end"]])
  end

  it "reads the pre-loop seed before the future body writer on the first iteration" do
    expect(execute(dataflow_config)[:history]).to eq(["seed"])
  end

  it "reads the last executed write on subsequent iterations" do
    expect(execute(dataflow_config(iterations: 3))[:history]).to eq(["seed", "body", "body"])
  end

  it "treats an explicit target as terminal even when it is another implicit loop pin" do
    config = dataflow_config(iterations: 2)
    config["elements"].insert(2, assignment("other_seed", "other", "original other"))
    config["elements"].insert(-2, assignment("other_writer", "other", "new other"))
    reader = config["elements"].find { |element| element["id"] == "reader" }
    reader["properties"]["steps"][0]["action"] = "template_render"
    reader["properties"]["steps"][0]["config"] = {
      "template" => "{{value}}|{{other}}",
      "resultVar" => "observed",
      "variables" => [
        { "key" => "value", "value" => "value" },
        { "key" => "other", "value" => "other" }
      ]
    }
    reader["properties"]["io_overrides"] = { "inputs" => [{ "pin" => "value", "override_key" => "other" }] }
    config["connections"].find { |edge| edge["from"] == "seed" }["to"] = "other_seed"
    config["connections"] << { "id" => "other_seed_gap", "from" => "other_seed", "to" => "gap" }
    config["connections"].find { |edge| edge["from"] == "loop" && edge["to"] == "reader" }["to"] = "other_writer"
    config["connections"] << { "id" => "other_writer_reader", "from" => "other_writer", "to" => "reader" }
    result = execute(config)
    expect(result[:history]).to eq(["original other|new other", "original other|new other"])
    expect(result[:other]).to eq("original other")
    expect(result[:value]).to eq("seed")
  end

  def branch_merge_config(reverse: false, reverse_edges: reverse)
    loop_id, alternate_id = reverse ? %w[z_loop a_alternate] : %w[a_loop z_alternate]
    loop_node = node(loop_id, "loop", "maxIterations" => 100, "condition" => {
      "type" => "group",
      "joins" => ["AND"],
      "conditions" => [
        { "kind" => "field", "leftOperand" => "ctx.params.run_loop", "operator" => "is_true", "rightOperand" => "" },
        { "kind" => "field", "leftOperand" => "ctx._loop_iteration_count", "operator" => "<", "rightOperand" => "1" }
      ]
    })
    alternate = assignment(alternate_id, "value", "alternate")
    writer = assignment("body_writer", "value", "body")
    write_body_gate = node("write_body_gate", "decision", boolean_decision("ctx.params.write_body"))
    write_alternate_gate = node("write_alternate_gate", "decision", boolean_decision("ctx.params.write_alternate"))
    branches = [loop_node, write_alternate_gate]
    branch_edges = [["decision", loop_id, "true"], ["decision", "write_alternate_gate", "false"]]
    branches.reverse! if reverse
    branch_edges.reverse! if reverse_edges
    elements = [node("start", "start"), assignment("seed", "value", "seed"),
      node("decision", "decision", boolean_decision("ctx.params.choose_loop")),
      *branches, write_body_gate, writer, alternate, node("merge", "process", "steps" => [
        action("merged_read", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "merged", "template" => "{{value}}")
      ]), node("end", "end")]
    configuration(elements, [["start", "seed"], ["seed", "decision"], *branch_edges,
      [loop_id, "write_body_gate"],
      ["write_body_gate", "body_writer", "true"], ["write_body_gate", loop_id, "false"],
      ["body_writer", loop_id],
      [loop_id, "merge"],
      ["write_alternate_gate", alternate_id, "true"], ["write_alternate_gate", "merge", "false"],
      [alternate_id, "merge"],
      ["merge", "end"]])
  end

  [false, true].each do |reverse|
    [false, true].each do |choose_loop|
      it "selects the executed merge value when branch IDs and edge order are reversed independently (#{reverse}, #{choose_loop})" do
        config = branch_merge_config(reverse: reverse, reverse_edges: !reverse)
        result = execute(config, params: { choose_loop: choose_loop, run_loop: true, write_body: true, write_alternate: true })
        expect(result[:merged]).to eq(choose_loop ? "body" : "alternate")
        expect(result[:value]).to eq("seed")
      end
    end
    [
      [true, true, true, true, "body"],
      [false, true, true, true, "alternate"],
      [true, false, true, true, "seed"],
      [true, true, false, true, "seed"],
      [false, true, true, false, "seed"]
    ].each do |choose_loop, run_loop, write_body, write_alternate, expected|
      it "merges the executed producer with reversed order #{reverse}, loop=#{choose_loop}, run=#{run_loop}, body=#{write_body}, alternate=#{write_alternate}" do
        config = branch_merge_config(reverse: reverse)
        result = execute(config, params: { choose_loop: choose_loop, run_loop: run_loop, write_body: write_body, write_alternate: write_alternate })
        expect(result[:merged]).to eq(expected)
        expect(result[:value]).to eq("seed")
      end
    end

    it "initializes a subsequent loop from the executed branch merge, with reversed order #{reverse}" do
      config = branch_merge_config(reverse: reverse)
      config["elements"].insert(-2, node("second_loop", "loop", "loopType" => "for_each",
        "collection" => "params.second_items", "maxIterations" => 100),
        node("second_reader", "process", "steps" => [action("second_read", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "second_initial", "template" => "{{value}}")]),
        assignment("second_writer", "value", "second body"),
        node("after", "process", "steps" => [action("after_read", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "final_value", "template" => "{{value}}")]))
      config["connections"].find { |edge| edge["from"] == "merge" }["to"] = "second_loop"
      config["connections"].concat(configuration([], [["second_loop", "second_reader"], ["second_reader", "second_writer"],
        ["second_writer", "second_loop"], ["second_loop", "after"], ["after", "end"]])["connections"].map { |edge| edge.merge("id" => "second_#{edge['id']}") })
      ctx = { params: { choose_loop: false, run_loop: true, write_body: true, write_alternate: true, second_items: [1] } }
      result = execute(config, ctx)
      expect(result[:second_initial]).to eq("alternate")
      expect(result[:final_value]).to eq("second body")
      # Reuse context to ensure an old alternate/loop export cannot win next run.
      ctx[:params].merge!(choose_loop: true, run_loop: false, write_alternate: false, second_items: [1])
      result = execute(config, ctx)
      expect(result[:second_initial]).to eq("seed")
      expect(result[:value]).to eq("seed")

      ctx[:params].merge!(choose_loop: false, write_alternate: true, second_items: [])
      result = execute(config, ctx)
      expect(result[:final_value]).to eq("alternate")
    end
  end

  [false, nil].each do |value|
    it "preserves an executed #{value.inspect} alternate value instead of falling back to the seed" do
      config = branch_merge_config
      alternate = config["elements"].find { |element| element["id"] == "z_alternate" }
      alternate["properties"]["steps"][0]["config"].merge!("valueType" => value.nil? ? "null" : "boolean", "booleanValue" => value)
      config["elements"].find { |element| element["id"] == "merge" }["properties"]["steps"] = [
        action("merged_read", "assign_value", "resultVar" => "merged", "valueType" => "ctx_ref", "ctxRefVariable" => "value")
      ]
      result = execute(config, params: { choose_loop: false, write_alternate: true })
      expect(result).to have_key(:merged)
      expect(result[:merged]).to eq(value)
      expect(result[:value]).to eq("seed")
    end
  end

  [true, false].each do |explicit|
    it "preserves the pre-loop #{explicit ? 'explicit original-pin' : 'implicit nearest-producer'} binding when a loop is appended" do
      config = dataflow_config(iterations: 2)
      config["elements"].insert(2, assignment("second", "value", "second"))
      gap = config["elements"].find { |element| element["id"] == "gap" }
      gap["properties"]["steps"] = [action("pre_read", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "pre_observed", "template" => "{{value}}")]
      gap["properties"]["io_overrides"] = { "inputs" => [{ "pin" => "value", "override_key" => "value" }] } if explicit
      config["connections"].find { |edge| edge["from"] == "seed" }["to"] = "second"
      config["connections"] << { "id" => "second_gap", "from" => "second", "to" => "gap" }

      without_loop = config.deep_dup
      without_loop["elements"].reject! { |element| %w[loop reader remember writer].include?(element["id"]) }
      without_loop["connections"].reject! { |edge| %w[loop reader remember writer].include?(edge["from"]) || %w[loop reader remember writer].include?(edge["to"]) }
      without_loop["connections"] << { "id" => "gap_end", "from" => "gap", "to" => "end" }
      expected = explicit ? "seed" : "second"
      expect(execute(without_loop)[:pre_observed]).to eq(expected)
      result = execute(config)
      expect(result[:pre_observed]).to eq(expected)
      expect(result[:history]).to eq(["second", "body"])
      expect(result[:value]).to eq("seed")
    end
  end

  it "gives sequential loops independent state initialized from the preceding loop's final value" do
    config = dataflow_config(iterations: 2)
    config["elements"].insert(-2, node("loop_two", "loop", "loopType" => "while", "maxIterations" => 100,
      "condition" => cond_group("ctx._loop_iteration_count", "<", "2")),
      node("reader_two", "process", "steps" => [
        action("read_two", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "observed_two", "template" => "{{value}}")
      ]),
      node("remember_two", "process", "steps" => [
        action("remember_two", "assign_value", "resultVar" => "history_two", "valueType" => "expression", "valueExpression" => "Array(ctx[:history_two]) + [ctx[:observed_two]]")
      ]), assignment("writer_two", "value", "body_two"),
      node("final", "process", "steps" => [action("final_read", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "final_value", "template" => "{{value}}")]))
    config["connections"].find { |edge| edge["from"] == "loop" && edge["to"] == "end" }["to"] = "loop_two"
    config["connections"].concat(configuration([], [["loop_two", "reader_two"], ["reader_two", "remember_two"],
        ["remember_two", "writer_two"], ["writer_two", "loop_two"], ["loop_two", "final"], ["final", "end"]])["connections"].map { |edge| edge.merge("id" => "second_#{edge['id']}") })

    result = execute(config)
    expect(result[:history]).to eq(%w[seed body])
    expect(result[:history_two]).to eq(%w[body body_two])
    expect(result[:final_value]).to eq("body_two")
    expect(result[:value]).to eq("seed")
    index = described_class.new(flowchart(config)).send(:build_element_io_index)
    expect(result[index[:rename_map].fetch("writer").fetch("value").to_sym]).to eq("body")
    expect(result[index[:rename_map].fetch("writer_two").fetch("value").to_sym]).to eq("body_two")
    first_slot = index[:loop_body_slots].fetch("writer").fetch("value")
    second_slot = index[:loop_body_slots].fetch("writer_two").fetch("value")
    expect(first_slot).not_to eq(second_slot)
    expect(first_slot).to eq("_loop_loop_step_value")
    expect(second_slot).to eq("_loop_loop_two_value")
    expect(first_slot).not_to match(/[0-9a-f]{64}/)
    expect(result[first_slot.to_sym]).to eq("body")
    expect(result[second_slot.to_sym]).to eq("body_two")
    source = index[:loop_initializers].fetch("loop_two").fetch(second_slot)
    expect(source).to include(pin: "value", candidates: ["loop:value", "seed:value"])

    config["elements"].find { |element| element["id"] == "loop_two" }["properties"]["condition"] =
      cond_group("ctx.params.run_second", "is_true")
    zero_trip = execute(config, params: { run_second: false }, second_slot.to_sym => "stale previous invocation")
    expect(zero_trip[:final_value]).to eq("body")
    expect(zero_trip[first_slot.to_sym]).to eq("body")
    expect(zero_trip[second_slot.to_sym]).to eq("body")
  end

  [false, true].each do |run_once|
    it "evaluates while structured conditions (runOnceFirst=#{run_once}) against updated state without modifying the seed" do
      config = dataflow_config(iterations: 10)
      config["elements"].find { |element| element["id"] == "seed" }["properties"]["steps"][0]["config"] = {
        "resultVar" => "value", "valueType" => "integer", "integerValue" => 0
      }
      config["elements"].find { |element| element["id"] == "loop" }["properties"].merge!(
        "loopType" => "while", "runOnceFirst" => run_once,
        "condition" => cond_group("ctx.value", "<", "2")
      )
      config["elements"].find { |element| element["id"] == "writer" }["properties"]["steps"][0]["config"] = {
        "resultVar" => "value", "valueType" => "expression", "valueExpression" => "ctx[:value] + 1"
      }
      result = execute(config)
      expect(result[:history]).to eq([0, 1])
      expect(result[:value]).to eq(0)
      expect(result[:_loop_iteration_count]).to eq(2)
    end
  end

  it "retains the seed when a body writer is skipped, then carries its actual write forward" do
    config = dataflow_config(iterations: 4)
    writer = config["elements"].find { |element| element["id"] == "writer" }
    gate = node("write_gate", "decision", "routeBy" => "condition",
      "condition" => cond_group("ctx._loop_iteration_count", "==", "2"))
    config["elements"].insert(config["elements"].index(writer), gate)
    remember_to_writer = config["connections"].find { |edge| edge["from"] == "remember" && edge["to"] == "writer" }
    remember_to_writer["to"] = "write_gate"
    config["connections"] << { "id" => "gate_writer", "from" => "write_gate", "to" => "writer", "matchValue" => "true" }
    config["connections"] << { "id" => "gate_loop", "from" => "write_gate", "to" => "loop", "matchValue" => "false" }
    expect(execute(config)[:history]).to eq(["seed", "seed", "body", "body"])
  end

  it "keeps read-before-write state and snapshots correct for composed actions without step ids" do
    config = dataflow_config(iterations: 2)
    writer = config["elements"].find { |element| element["id"] == "writer" }
    last = node("last", "process", "steps" => [
      action("last", "assign_value", "resultVar" => "done", "valueType" => "boolean", "booleanValue" => true)
    ])
    config["elements"].insert(config["elements"].index(writer) + 1, last)
    config["elements"].each { |element| Array(element.dig("properties", "steps")).each { |step| step.delete("id") } }
    config["connections"].find { |edge| edge["from"] == "writer" }["to"] = "last"
    config["connections"] << { "id" => "last_loop", "from" => "last", "to" => "loop" }
    result = execute(config)
    expect(result[:history]).to eq(%w[seed body])
    expect(result[:value]).to eq("seed")
  end

  it "publishes an explicitly aliased body snapshot without overwriting the seed" do
    config = dataflow_config(iterations: 2)
    writer = config["elements"].find { |element| element["id"] == "writer" }
    writer["properties"]["io_overrides"] = { "outputs" => [{ "pin" => "value", "renamed_to" => "body_snapshot" }] }
    result = execute(config)
    expect(result[:history]).to eq(%w[seed body])
    expect(result[:value]).to eq("seed")
    expect(result[:body_snapshot]).to eq("body")
  end

  it "carries only executed branch writes across continue iterations" do
    config = dataflow_config(iterations: 5)
    config["elements"].find { |element| element["id"] == "loop" }["properties"].merge!(
      "loopType" => "for_each", "collection" => "params.modes"
    )
    config["elements"].insert(-2, node("route", "decision", value_decision("ctx[:item]")),
      assignment("other_writer", "value", "other"))
    config["connections"].find { |edge| edge["from"] == "remember" }["to"] = "route"
    config["connections"].concat([
      { "id" => "continue", "from" => "route", "to" => "loop", "matchValue" => "skip" },
      { "id" => "body", "from" => "route", "to" => "writer", "matchValue" => "body" },
      { "id" => "other", "from" => "route", "to" => "other_writer", "matchValue" => "other" },
      { "id" => "other_back", "from" => "other_writer", "to" => "loop" }
    ])
    ctx = execute(config, params: { modes: %w[skip body skip other skip] })
    expect(ctx[:history]).to eq(%w[seed seed body body other])
  end

  it "reads the latest executed body write after loop exit" do
    config = dataflow_config(iterations: 2)
    config["elements"].insert(-2, node("after", "process", "steps" => [
      action("final", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "final_value", "template" => "{{value}}")
    ]))
    config["connections"].find { |edge| edge["from"] == "loop" && edge["to"] == "end" }["to"] = "after"
    config["connections"] << { "id" => "after_end", "from" => "after", "to" => "end" }
    expect(execute(config)[:final_value]).to eq("body")
  end

  it "does not bind an exit reader to an unexecuted writer when the loop is initially false" do
    config = dataflow_config
    config["elements"].find { |element| element["id"] == "loop" }["properties"]["condition"] =
      cond_group("ctx.params.run", "is_true")
    config["elements"].insert(-2, node("after", "process", "steps" => [
      action("final", "assign_value", "valueType" => "ctx_ref", "ctxRefVariable" => "value", "resultVar" => "final_value", "template" => "{{value}}")
    ]))
    config["connections"].find { |edge| edge["from"] == "loop" && edge["to"] == "end" }["to"] = "after"
    config["connections"] << { "id" => "after_end", "from" => "after", "to" => "end" }
    expect(execute(config, params: { run: false })[:final_value]).to eq("seed")
  end

  it "honors an explicitly named seed snapshot instead of the implicit mutable loop variable" do
    config = dataflow_config(iterations: 3)
    seed = config["elements"].find { |element| element["id"] == "seed" }
    seed["properties"]["io_overrides"] = { "outputs" => [{ "pin" => "value", "renamed_to" => "initial_value" }] }
    reader = config["elements"].find { |element| element["id"] == "reader" }
    reader["properties"]["io_overrides"] = { "inputs" => [{ "pin" => "value", "override_key" => "initial_value" }] }
    expect(execute(config)[:history]).to eq(["seed", "seed", "seed"])
  end

  it "does not treat a future iteration's output as an available initial input" do
    config = dataflow_config
    config["elements"].find { |element| element["id"] == "seed" }["properties"]["steps"] = []
    result = FlowchartInputOutputValidator.call(flowchart(config))
    expect(result.valid?).to eq(false)
    expect(result.errors).to include(hash_including(element_id: "reader", missing_input: "value"))
  end

  it "reports nested loops through full server validation" do
    config = dataflow_config
    config["elements"].insert(-2, node("inner", "loop", "loopType" => "while", "maxIterations" => 2,
      "condition" => cond_group("ctx.go", "is_true")), node("inner_work", "process"))
    config["connections"].find { |edge| edge["from"] == "loop" && edge["to"] == "reader" }["to"] = "inner"
    config["connections"].concat([
      { "id" => "inner_body", "from" => "inner", "to" => "inner_work" },
      { "id" => "inner_back", "from" => "inner_work", "to" => "inner" },
      { "id" => "inner_exit", "from" => "inner", "to" => "reader" }
    ])
    problems = FlowchartServerValidator.new(flowchart(config), config).call
    expect(problems).to include(hash_including(type: "codegen_failed",
      message: a_string_including(I18n.t("code_generator_validation.loop_topology.nested_loop"))))
  end

  it "localizes the structured ActivityGenerator error and server validation detail" do
    config = configuration([node("start", "start"), node("loop", "loop", "loopType" => "for_each"), node("end", "end")],
      [["start", "loop"], ["loop", "end"]])
    record = flowchart(config)
    I18n.with_locale(:"zh-CN") do
      expect { described_class.new(record).generate }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
        expect(error.element_id).to eq("loop")
        expect(error.message).to eq("代码生成器配置无效：必须填写 collection")
      }
      expect(FlowchartServerValidator.new(record, config).call).to include(hash_including(
        type: "element_config_invalid", element_id: "loop", message: a_string_including("必须填写 collection")
      ))
    end
    I18n.with_locale(:en) do
      expect { described_class.new(record).generate }.to raise_error(ActivityGenerator::Error,
        "Invalid generator configuration: collection is required")
    end
  end

  [2, 3].each do |branch_count|
    %w[skip a b].first(branch_count).each do |mode|
      it "validates and executes #{branch_count} body branches with a direct continue (#{mode})" do
        elements = [node("start", "start"), node("loop", "loop", "loopType" => "while", "maxIterations" => 100,
          "condition" => cond_group("ctx._loop_iteration_count", "<", "2")),
          node("route", "decision", value_decision("ctx.dig(:params, :mode)")),
          assignment("a", "a_ran", "yes"), node("end", "end")]
        edges = [["start", "loop"], ["loop", "route"], ["loop", "end"],
          ["route", "loop", "skip"], ["route", "a", "a"], ["a", "loop"]]
        if branch_count == 3
          elements.insert(-2, assignment("b", "b_ran", "yes"))
          edges.concat([["route", "b", "b"], ["b", "loop"]])
        end
        ctx = execute(configuration(elements, edges), params: { mode: mode })
        expect(ctx[:_loop_iteration_count]).to eq(2)
        expect(ctx[:a_ran]).to eq(mode == "a" ? "yes" : nil)
        expect(ctx[:b_ran]).to eq(mode == "b" ? "yes" : nil)
      end
    end
  end
end
