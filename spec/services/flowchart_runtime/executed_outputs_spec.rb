# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ExecutedOutputs do
  let(:execution) { { key: "execution", pins: ["value"] } }
  let(:source) { { execution: "execution", candidates: %w[left:value right:value], pin: "value" } }

  it "selects the latest eligible executed producer, including false, regardless of candidate order" do
    ctx = { value: "seed" }
    described_class.start(ctx, execution)
    described_class.publish(ctx, { execution: "execution", producer: "right:value" }, true, "right")
    described_class.publish(ctx, { execution: "execution", producer: "left:value" }, true, false)
    described_class.publish(ctx, { execution: "execution", producer: "unrelated:value" }, true, "unrelated")
    expect(described_class.read(ctx, source)).to eq([true, false])
    expect(described_class.read(ctx, source.merge(candidates: source[:candidates].reverse))).to eq([true, false])
    expect(ctx[:value]).to eq("seed")
  end

  it "uses the invocation's initial context when no eligible producer wrote" do
    ctx = { value: "seed", old_snapshot: "stale branch" }
    described_class.start(ctx, execution)
    expect(described_class.read(ctx, source)).to eq([true, "seed"])
    expect(described_class.read(ctx, "old_snapshot")).to eq([true, "stale branch"])
  end

  it "clears old provenance on every invocation" do
    ctx = { value: "seed" }
    described_class.start(ctx, execution)
    described_class.publish(ctx, { execution: "execution", producer: "left:value" }, true, "old branch")
    described_class.start(ctx, execution)
    expect(described_class.read(ctx, source)).to eq([true, "seed"])
  end

  it "does not reset an already-started registry from ensure_started" do
    ctx = { value: "seed" }
    described_class.start(ctx, execution)
    described_class.publish(ctx, { execution: "execution", producer: "left:value" }, true, "kept")
    described_class.ensure_started(ctx, execution)
    expect(described_class.read(ctx, source)).to eq([true, "kept"])
  end

  it "distinguishes an executed absent export from a present nil and an unexecuted candidate" do
    ctx = { value: "seed", slot: nil }
    described_class.start(ctx, execution)
    publication = { execution: "execution", producer: "left:value" }
    described_class.export(ctx, publication, :slot)
    expect(described_class.read_context(ctx, source)).to eq(value: nil)
    ctx.delete(:slot)
    described_class.export(ctx, publication, :slot)
    expect(described_class.read_context(ctx, source)).to eq({})
  end

  it "initializes explicit sources terminally and removes stale slots for absent inputs" do
    ctx = { original: "snapshot", slot: "stale" }
    described_class.start(ctx, execution)
    described_class.initialize_slot(ctx, :slot, "original")
    expect(ctx[:slot]).to eq("snapshot")
    described_class.initialize_slot(ctx, :slot, source)
    expect(ctx).not_to have_key(:slot)
  end

  it "raises Error for invalid execution input" do
    expect { described_class.start({}, nil) }.to raise_error(described_class::Error)
    expect { described_class.start({}, {}) }.to raise_error(described_class::Error)
  end

  it "fetches the latest candidate value for a generated read" do
    ctx = { value: "seed" }
    described_class.start(ctx, execution)
    described_class.publish(ctx, { execution: "execution", producer: "left:value" }, true, "left")
    expect(described_class.fetch(ctx, :value, candidates: %w[left:value right:value], execution: "execution")).to eq("left")
  end
end
