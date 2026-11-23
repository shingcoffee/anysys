# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Loop do
  let(:execution) { { key: "_loop_io", pins: ["value"] } }

  it "stores iteration state under one short key and removes it on leave" do
    ctx = { value: "seed" }
    state = described_class.enter(ctx, :_each_item, execution: "_loop_io", pins: ["value"], initializers: {}, state: { index: 0 })
    expect(state).to eq(index: 0)
    expect(ctx[:_each_item]).to eq(index: 0)
    described_class.leave(ctx, :_each_item, {})
    expect(ctx).not_to have_key(:_each_item)
  end

  it "does not replace existing state on a later enter of the same invocation" do
    ctx = {}
    described_class.enter(ctx, :_repeat, state: { count: 0 })
    ctx[:_repeat][:count] = 2
    described_class.enter(ctx, :_repeat, state: { count: 0 })
    expect(ctx[:_repeat][:count]).to eq(2)
  end

  it "exports slots on leave" do
    ctx = { value: "seed" }
    described_class.enter(ctx, :_repeat, execution: "_loop_io", pins: ["value"], initializers: { _loop_repeat_value: "value" }, state: { count: 0 })
    ctx[:_loop_repeat_value] = "body"
    described_class.leave(ctx, :_repeat, { _loop_repeat_value: { execution: "_loop_io", producer: "loop:value" } })
    expect(FlowchartRuntime::ExecutedOutputs.read(ctx, { execution: "_loop_io", candidates: ["loop:value"], pin: "value" })).to eq([true, "body"])
  end

  it "raises Error for a blank loop key" do
    expect { described_class.enter({}, nil) }.to raise_error(described_class::Error)
    expect { described_class.leave({}, "  ") }.to raise_error(described_class::Error)
  end

  it "leaves then fails with loop_limit" do
    ctx = {}
    described_class.enter(ctx, :_repeat, state: { count: 3 })

    expect(described_class.fail_limit(ctx, :_repeat, max: 3)).to be(false)
    expect(ctx).not_to have_key(:_repeat)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 3)])
    expect(ctx[:error_details].first).to include("code" => "loop_limit", "details" => { max: "3" })
  end
end
