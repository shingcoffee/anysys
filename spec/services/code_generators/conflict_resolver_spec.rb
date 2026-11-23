require "rails_helper"

RSpec.describe CodeGenerators::ConflictResolver do
  def element(id, emits: [])
    { id: id, outputs: emits.map { |pin| { pin: pin } } }
  end

  def ancestors_for(map)
    map.transform_values { |ids| ids.to_set }
  end

  it "returns an empty rename map when every key has a single emitter" do
    elements = [element("a", emits: ["x"]), element("b", emits: ["y"])]
    expect(described_class.call(elements)).to eq({})
  end

  it "keeps the original key for writers on exclusive branches" do
    elements = [element("left", emits: ["reviewer"]), element("right", emits: ["reviewer"])]
    result = described_class.call(
      elements,
      topo_order: %w[start left right merge],
      ancestors: ancestors_for("left" => %w[start], "right" => %w[start], "merge" => %w[start left right])
    )
    expect(result).to eq({})
  end

  it "renames a writer when another writer of the same pin is an ancestor" do
    elements = [element("seed", emits: ["status"]), element("approved", emits: ["status"])]
    result = described_class.call(
      elements,
      topo_order: %w[start seed decision approved merge],
      ancestors: ancestors_for(
        "seed" => %w[start],
        "approved" => %w[start seed decision],
        "merge" => %w[start seed decision approved]
      )
    )
    expect(result.keys).to match_array(%w[approved])
    expect(result["seed"]).to be_nil
    expect(result["approved"]["status"]).to match(/\Astatus_[0-9a-f]{4}\z/)
  end

  it "renames every writer that has an upstream writer of the same pin" do
    elements = [
      element("seed", emits: ["x"]),
      element("left", emits: ["x"]),
      element("right", emits: ["x"])
    ]
    result = described_class.call(
      elements,
      topo_order: %w[seed left right],
      ancestors: ancestors_for("left" => %w[seed], "right" => %w[seed], "seed" => [])
    )
    expect(result["seed"]).to be_nil
    expect(result["left"]["x"]).to match(/\Ax_[0-9a-f]{4}\z/)
    expect(result["right"]["x"]).to match(/\Ax_[0-9a-f]{4}\z/)
  end

  it "lets terminal Ends on exclusive branches share response" do
    elements = [element("end_a", emits: ["response"]), element("end_b", emits: ["response"])]
    result = described_class.call(
      elements,
      topo_order: %w[start end_a end_b],
      ancestors: ancestors_for("end_a" => %w[start], "end_b" => %w[start])
    )
    expect(result).to eq({})
  end

  it "is deterministic across calls when an ancestor forces a rename" do
    elements = [element("a", emits: ["model"]), element("b", emits: ["model"])]
    kwargs = { topo_order: %w[a b], ancestors: ancestors_for("b" => %w[a], "a" => []) }
    first = described_class.call(elements, **kwargs)
    expect(described_class.call(elements, **kwargs)).to eq(first)
    expect(first["b"]["model"]).to match(/\Amodel_[0-9a-f]{4}\z/)
  end

  it "does not collide when the effective keys already differ" do
    elements = [element("a", emits: ["model_a3f2"]), element("b", emits: ["model"])]
    expect(described_class.call(elements)).to eq({})
  end

  it "falls back to 6-char suffix on 4-char prefix collision among renamed writers" do
    hit = 0
    allow(Digest::SHA1).to receive(:hexdigest).and_wrap_original do |orig, input|
      hit += 1
      hit <= 2 ? "dead" + ("beef" * 9) : orig.call(input)
    end
    elements = [element("a", emits: ["x"]), element("b", emits: ["x"]), element("c", emits: ["x"])]
    result = described_class.call(
      elements,
      topo_order: %w[a b c],
      ancestors: ancestors_for("b" => %w[a], "c" => %w[a], "a" => [])
    )
    expect(result["a"]).to be_nil
    expect(result["b"]["x"]).to match(/\Ax_[0-9a-f]{6}\z/)
    expect(result["c"]["x"]).to match(/\Ax_[0-9a-f]{6}\z/)
  end
end
