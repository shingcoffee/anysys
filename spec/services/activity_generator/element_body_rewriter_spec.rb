# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::ElementBodyRewriter do
  def rewrite(body, io_index)
    element = { "id" => "merge", "properties" => {} }
    described_class.new(io_index).call(element, body)
  end

  it "passes dominators through so a non-dominating merge reads Outputs.latest" do
    io_index = {
      rename_map: {
        "left" => { "status" => "status_left" },
        "right" => { "status" => "status_right" }
      },
      reachability: { "merge" => %w[start left right] },
      producer_outputs: { "left" => %w[status], "right" => %w[status], "merge" => [] },
      dominators: { "merge" => %w[start merge].to_set },
      topo_index: { "start" => 0, "left" => 1, "right" => 2, "merge" => 3 }
    }
    result = rewrite("ctx[:summary] = ctx[:status]", io_index)
    expect(result).to eq("ctx[:summary] = FlowchartRuntime::Outputs.latest(ctx, :status_right, :status_left)")
  end

  it "reads a dominating latest producer directly on the ordinary path" do
    io_index = {
      rename_map: { "near" => { "status" => "status_near" } },
      reachability: { "merge" => %w[far near] },
      producer_outputs: { "far" => %w[status], "near" => %w[status], "merge" => [] },
      dominators: { "merge" => %w[far near merge].to_set },
      topo_index: { "far" => 0, "near" => 1, "merge" => 2 }
    }
    result = rewrite("x = ctx[:status]", io_index)
    expect(result).to eq("x = ctx[:status_near]")
  end

  def loop_index(overrides = {})
    {
      loop_execution: { key: "_loop_io", pins: ["total"] },
      loop_region_ids: Set.new(["merge"]),
      loop_body_slots: { "merge" => {} },
      loop_publications: { "merge" => {} },
      loop_reads: { "merge" => {} },
      producer_outputs: { "merge" => %w[item index _loop_iteration_count] },
      rename_map: {},
      reachability: { "merge" => [] }
    }.merge(overrides)
  end

  it "leaves provenance-free loop writes as plain ctx assignment" do
    body = "ctx[:item] = item\nctx[:index] = index\nctx[:_loop_iteration_count] = state[:count]\ntrue"
    expect(rewrite(body, loop_index)).to eq(body)
  end

  it "emits LoopState.write for a published loop pin and keeps Slot for operator writes" do
    io_index = loop_index(
      loop_body_slots: { "merge" => { "total" => "_loop_each_item_total" } },
      loop_publications: { "merge" => { "total" => { execution: "_loop_io", producer: "add:total" } } },
      producer_outputs: { "merge" => %w[total] }
    )
    written = rewrite("ctx[:total] = 0", io_index)
    expect(written).to include("FlowchartRuntime::LoopState.write(")
    expect(written).to include("producer:")
    expect(written).not_to include("LoopState::Slot.new")
    expect(written).not_to include("ActivityGenerator::")

    operator = rewrite("ctx[:total] += 1", io_index)
    expect(operator).to include("FlowchartRuntime::LoopState::Slot.new")
  end

  it "does not splice implied Entries.scope(ctx) reads in a loop participant" do
    io_index = loop_index(
      loop_body_slots: { "merge" => { "total" => "_loop_each_item_total" } },
      loop_publications: { "merge" => { "total" => { execution: "_loop_io", producer: "add:total" } } },
      loop_reads: { "merge" => { "bound_entity" => { execution: "_loop_io", candidates: ["seed:bound_entity"], pin: "bound_entity" } } },
      producer_outputs: { "merge" => %w[total bound_entity] }
    )
    body = "ctx[:total] = 1\nFlowchartRuntime::Entries.scope(ctx)\ntrue"
    result = rewrite(body, io_index)
    expect(result).to include("FlowchartRuntime::Entries.scope(ctx)")
    expect(result).not_to include("Entries.scope(FlowchartRuntime")
    expect(result).to include("FlowchartRuntime::LoopState.write(")
  end
end
