# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::LoopState do
  def execute(source, ctx, read: "state")
    bindings = { "value" => { snapshot: "snapshot", state: "state", read: read } }
    code = described_class.rewrite(source, bindings, reads: { "value" => read })
    eval("->(ctx) do\n#{code}\nend").call(ctx)
  end

  it "publishes only an executed assignment and evaluates its value once" do
    ctx = { original: "seed", state: "second", calls: 0 }
    execute("ctx[:value] = (ctx[:calls] += 1) if false", ctx)
    expect(ctx).to eq(original: "seed", state: "second", calls: 0)
    execute("ctx[:value] = (ctx[:calls] += 1)", ctx)
    expect(ctx).to eq(original: "seed", state: 1, snapshot: 1, calls: 1)
  end

  it "handles operator assignments using the current state, not a stale snapshot" do
    ctx = { state: 2, snapshot: 100 }
    execute("ctx[:value] += 3", ctx)
    expect(ctx.values_at(:state, :snapshot)).to eq([5, 5])
  end

  it "honors explicit input snapshot selection for a read-modify-write" do
    ctx = { original: 1, state: 2, snapshot: 100 }
    execute("ctx[:value] += 3", ctx, read: "original")
    expect(ctx.values_at(:original, :state, :snapshot)).to eq([1, 4, 4])
  end

  it "preserves ||= and &&= short-circuit semantics, including false and nil" do
    ctx = { state: false }
    execute("ctx[:value] &&= raise('not evaluated')", ctx)
    expect(ctx).to eq(state: false)
    execute("ctx[:value] ||= 3", ctx)
    expect(ctx).to eq(state: 3, snapshot: 3)
    execute("ctx[:value] ||= raise('not evaluated')", ctx)
    execute("ctx[:value] &&= nil", ctx)
    expect(ctx).to eq(state: nil, snapshot: nil)
  end

  it "supports parallel assignment and leaves unrelated context keys alone" do
    ctx = {}
    execute("ctx[:value], ctx[:other] = [false, 2]", ctx)
    expect(ctx).to eq(state: false, snapshot: false, other: 2)
  end

  it "maps dig/fetch roots while preserving nested keys and defaults" do
    ctx = { state: { nested: "current" }, value: { nested: "seed" } }
    result = execute("[ctx.dig(:value, :nested), ctx.fetch(:value), ctx.fetch(:other, :default)]", ctx)
    expect(result).to eq(["current", { nested: "current" }, :default])
  end

  it "maps reads even when ctx is a local variable and preserves key presence" do
    ctx = { state: 2, value: 100 }
    execute("ctx = ctx; ctx[:value] = ctx[:value] + 1", ctx)
    expect(ctx).to eq(state: 3, snapshot: 3, value: 100)
    ctx.delete(:state)
    expect(execute("[ctx.key?(:value), ctx.fetch(:value, :missing)]", ctx)).to eq([false, :missing])
  end

  it "uses byte-safe AST positions and never rewrites strings or comments" do
    ctx = {}
    result = execute(%(label = "中文 ctx[:value] = 1"; ctx[:value] = "中文"\n# ctx[:value] = 2\nlabel), ctx)
    expect(result).to eq("中文 ctx[:value] = 1")
    expect(ctx).to eq(state: "中文", snapshot: "中文")
  end

  it "emits FlowchartRuntime constants, not ActivityGenerator" do
    code = described_class.rewrite("ctx[:value] = 1", { "value" => { snapshot: "snapshot", state: "state", read: "state", publication: { execution: "_loop_io", producer: "add:value" } } })
    expect(code).to include("FlowchartRuntime::LoopState.write(")
    expect(code).not_to include("ActivityGenerator::")
    expect(code).not_to include("LoopState::Slot.new")
  end

  it "keeps Slot only for operator writes" do
    code = described_class.rewrite("ctx[:value] += 1", { "value" => { snapshot: "snapshot", state: "state", read: "state", publication: { execution: "_loop_io", producer: "add:value" } } })
    expect(code).to include("FlowchartRuntime::LoopState::Slot.new")
  end

  it "leaves provenance-free writes as plain ctx assignment" do
    code = described_class.rewrite("ctx[:item] = item", { "item" => { snapshot: "item", state: nil, read: "item", publication: nil } })
    expect(code).to eq("ctx[:item] = item")
  end

  it "rewrites provenance reads through ExecutedOutputs.fetch" do
    source = { execution: "_loop_io", candidates: %w[loop:total init:total], pin: "total" }
    code = described_class.rewrite("x = ctx[:total]", {}, reads: { "total" => source })
    expect(code).to include("FlowchartRuntime::ExecutedOutputs.fetch(ctx, :total, candidates:")
    expect(code).not_to include("read_context")
  end

  it "does not rewrite implied Entries.scope(ctx) argument spans" do
    body = "FlowchartRuntime::Entries.scope(ctx)\nctx[:value] = 1"
    code = described_class.rewrite(body, { "value" => { snapshot: "snapshot", state: "state", read: "state", publication: { execution: "_loop_io", producer: "add:value" } } }, reads: { "bound_entity" => { execution: "_loop_io", candidates: ["seed:bound_entity"], pin: "bound_entity" } })
    expect(code).to include("FlowchartRuntime::Entries.scope(ctx)")
    expect(code).not_to include("Entries.scope(FlowchartRuntime")
  end
end
