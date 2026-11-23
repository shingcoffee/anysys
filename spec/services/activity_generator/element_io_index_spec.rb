# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::ElementIoIndex do
  # Helper: build a minimal element hash that ElementIoIndex can process.
  # We use 'start' / 'end' types because IoExtractor#call_element returns
  # EMPTY for unknown generator types, so these produce no output pins —
  # making topological / reachability tests simpler and DB-free.
  def el(id:, type: "start")
    { "id" => id, "type" => type, "properties" => {} }
  end

  def conn(from:, to:)
    { "from" => from, "to" => to }
  end

  # A topological_order_provider built from a real GraphBuilder.
  def topo_provider(elements, connections)
    -> { ActivityGenerator::GraphBuilder.new(elements, connections).build.topological_order }
  end

  # The built index for the per-describe `elements`/`connections`.
  subject(:result) do
    described_class.new(elements, connections, topological_order_provider: topo_provider(elements, connections)).build
  end

  # -----------------------------------------------------------------------
  # #build — return shape
  # -----------------------------------------------------------------------
  describe "#build return shape" do
    let(:elements) { [el(id: "s1"), el(id: "e1", type: "end")] }
    let(:connections) { [conn(from: "s1", to: "e1")] }


    it "returns a Hash" do
      expect(result).to be_a(Hash)
    end

    it "includes :rename_map key" do
      expect(result).to have_key(:rename_map)
    end

    it "includes :reachability key" do
      expect(result).to have_key(:reachability)
    end

    it "includes :producer_outputs key" do
      expect(result).to have_key(:producer_outputs)
    end

    it "includes :dominators key" do
      expect(result).to have_key(:dominators)
    end

    it "includes :topo_index key" do
      expect(result).to have_key(:topo_index)
    end

    it "rename_map is a Hash" do
      expect(result[:rename_map]).to be_a(Hash)
    end

    it "reachability is a Hash keyed by element id" do
      expect(result[:reachability].keys).to contain_exactly("s1", "e1")
    end

    it "producer_outputs is a Hash keyed by element id" do
      expect(result[:producer_outputs].keys).to contain_exactly("s1", "e1")
    end
  end

  # -----------------------------------------------------------------------
  # Reachability — simple linear graph
  # -----------------------------------------------------------------------
  describe "reachability — linear graph (BFS predecessors)" do
    # s1 -> p1 -> e1
    let(:elements) do
      [el(id: "s1"), el(id: "p1", type: "process"), el(id: "e1", type: "end")]
    end

    let(:connections) do
      [conn(from: "s1", to: "p1"), conn(from: "p1", to: "e1")]
    end


    it "start element has no predecessors" do
      expect(result[:reachability]["s1"]).to be_empty
    end

    it "middle element lists only the start as predecessor" do
      expect(result[:reachability]["p1"]).to include("s1")
    end

    it "end element lists both s1 and p1 as predecessors (farthest-first)" do
      predecessors = result[:reachability]["e1"]
      expect(predecessors).to include("s1")
      expect(predecessors).to include("p1")
      # farthest-first: s1 should appear before p1
      expect(predecessors.index("s1")).to be < predecessors.index("p1")
    end
  end

  # -----------------------------------------------------------------------
  # Reachability — no connections
  # -----------------------------------------------------------------------
  describe "reachability — no connections" do
    let(:elements) { [el(id: "a"), el(id: "b")] }
    let(:connections) { [] }


    it "all elements have empty predecessor lists" do
      expect(result[:reachability]["a"]).to be_empty
      expect(result[:reachability]["b"]).to be_empty
    end
  end

  # -----------------------------------------------------------------------
  # Reachability — branching graph
  # -----------------------------------------------------------------------
  describe "reachability — branching graph" do
    # s1 -> p1, s1 -> p2, p1 -> e1, p2 -> e1
    let(:elements) do
      [
        el(id: "s1"),
        el(id: "p1", type: "process"),
        el(id: "p2", type: "process"),
        el(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        conn(from: "s1", to: "p1"),
        conn(from: "s1", to: "p2"),
        conn(from: "p1", to: "e1"),
        conn(from: "p2", to: "e1")
      ]
    end


    it "end element has all three predecessors" do
      predecessors = result[:reachability]["e1"]
      expect(predecessors).to include("s1", "p1", "p2")
    end
  end

  # -----------------------------------------------------------------------
  # Dominators — diamond, nested diamond, branch to End
  # -----------------------------------------------------------------------
  describe "dominators — diamond" do
    # s1 -> p1 -> e1
    #    -> p2 ->
    let(:elements) do
      [
        el(id: "s1"),
        el(id: "p1", type: "process"),
        el(id: "p2", type: "process"),
        el(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        conn(from: "s1", to: "p1"),
        conn(from: "s1", to: "p2"),
        conn(from: "p1", to: "e1"),
        conn(from: "p2", to: "e1")
      ]
    end

    it "records start and the merge node as the merge's dominators" do
      expect(result[:dominators]["e1"]).to eq(%w[s1 e1].to_set)
    end

    it "does not treat either branch as dominating the merge" do
      expect(result[:dominators]["e1"]).not_to include("p1", "p2")
    end

    it "dominates each branch node by start and itself" do
      expect(result[:dominators]["p1"]).to eq(%w[s1 p1].to_set)
      expect(result[:dominators]["p2"]).to eq(%w[s1 p2].to_set)
    end
  end

  describe "dominators — nested diamond" do
    # s1 -> outer -> a -> inner -> c -> merge
    #             -> b ->      -> d ->
    let(:elements) do
      [
        el(id: "s1"),
        el(id: "outer", type: "decision"),
        el(id: "a", type: "process"),
        el(id: "b", type: "process"),
        el(id: "inner", type: "decision"),
        el(id: "c", type: "process"),
        el(id: "d", type: "process"),
        el(id: "merge", type: "process")
      ]
    end

    let(:connections) do
      [
        conn(from: "s1", to: "outer"),
        conn(from: "outer", to: "a"),
        conn(from: "outer", to: "b"),
        conn(from: "a", to: "inner"),
        conn(from: "b", to: "inner"),
        conn(from: "inner", to: "c"),
        conn(from: "inner", to: "d"),
        conn(from: "c", to: "merge"),
        conn(from: "d", to: "merge")
      ]
    end

    it "dominates the outer merge by start, both decisions, and itself" do
      expect(result[:dominators]["merge"]).to eq(%w[s1 outer inner merge].to_set)
    end

    it "does not let a nested-diamond branch dominate the outer merge" do
      expect(result[:dominators]["merge"]).not_to include("a", "b", "c", "d")
    end

    it "dominates an inner-diamond branch by the inner decision" do
      expect(result[:dominators]["c"]).to include("s1", "outer", "inner", "c")
      expect(result[:dominators]["c"]).not_to include("d", "a", "b")
    end
  end

  describe "dominators — branch to End" do
    # s1 -> d -> a -> end1
    #         -> b -> end2
    let(:elements) do
      [
        el(id: "s1"),
        el(id: "d", type: "decision"),
        el(id: "a", type: "process"),
        el(id: "b", type: "process"),
        el(id: "end1", type: "end"),
        el(id: "end2", type: "end")
      ]
    end

    let(:connections) do
      [
        conn(from: "s1", to: "d"),
        conn(from: "d", to: "a"),
        conn(from: "d", to: "b"),
        conn(from: "a", to: "end1"),
        conn(from: "b", to: "end2")
      ]
    end

    it "dominates each End by its own branch and not the other" do
      expect(result[:dominators]["end1"]).to eq(%w[s1 d a end1].to_set)
      expect(result[:dominators]["end2"]).to eq(%w[s1 d b end2].to_set)
    end
  end

  describe "topo_index — linear graph" do
    let(:elements) do
      [el(id: "s1"), el(id: "p1", type: "process"), el(id: "e1", type: "end")]
    end

    let(:connections) do
      [conn(from: "s1", to: "p1"), conn(from: "p1", to: "e1")]
    end

    it "assigns increasing indexes along the unique path" do
      expect(result[:topo_index]["s1"]).to be < result[:topo_index]["p1"]
      expect(result[:topo_index]["p1"]).to be < result[:topo_index]["e1"]
    end
  end

  describe "rename_map — exclusive branch writers keep the original pin" do
    let(:elements) do
      [
        el(id: "s1"),
        el(id: "d1", type: "decision"),
        {
          "id" => "p1", "type" => "process", "properties" => {
            "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "reviewer", "valueType" => "string", "stringValue" => "manager" } }]
          }
        },
        {
          "id" => "p2", "type" => "process", "properties" => {
            "steps" => [{ "action" => "assign_value", "config" => { "resultVar" => "reviewer", "valueType" => "string", "stringValue" => "team" } }]
          }
        },
        el(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        conn(from: "s1", to: "d1"),
        conn(from: "d1", to: "p1"),
        conn(from: "d1", to: "p2"),
        conn(from: "p1", to: "e1"),
        conn(from: "p2", to: "e1")
      ]
    end

    it "does not rename either exclusive writer" do
      expect(result[:rename_map]["p1"]).to be_nil
      expect(result[:rename_map]["p2"]).to be_nil
    end
  end

  describe "rename_map — author output overrides win" do
    def process_assign(id, pin, value, renamed_to: nil)
      props = {
        "steps" => [{
          "action" => "assign_value",
          "config" => { "resultVar" => pin, "valueType" => "string", "stringValue" => value }
        }]
      }
      if renamed_to
        props["io_overrides"] = { "outputs" => [{ "pin" => pin, "renamed_to" => renamed_to }] }
      end
      { "id" => id, "type" => "process", "properties" => props }
    end

    describe "linear overwrite with a persisted renamed_to" do
      let(:elements) do
        [
          el(id: "s1"),
          process_assign("seed", "v", "seed"),
          process_assign("overwrite", "v", "over", renamed_to: "author_v"),
          el(id: "e1", type: "end")
        ]
      end

      let(:connections) do
        [conn(from: "s1", to: "seed"), conn(from: "seed", to: "overwrite"), conn(from: "overwrite", to: "e1")]
      end

      it "folds the author's renamed_to over the conflict-resolver suffix" do
        expect(result[:rename_map].dig("overwrite", "v")).to eq("author_v")
        expect(result[:rename_map].dig("seed", "v")).to be_nil
      end
    end

    describe "exclusive writers with custom renames" do
      let(:elements) do
        [
          el(id: "s1"),
          el(id: "d1", type: "decision"),
          process_assign("p1", "v", "left", renamed_to: "left_v"),
          process_assign("p2", "v", "right", renamed_to: "right_v"),
          el(id: "e1", type: "end")
        ]
      end

      let(:connections) do
        [
          conn(from: "s1", to: "d1"),
          conn(from: "d1", to: "p1"),
          conn(from: "d1", to: "p2"),
          conn(from: "p1", to: "e1"),
          conn(from: "p2", to: "e1")
        ]
      end

      it "records each author's renamed_to so merge readers can see both keys" do
        expect(result[:rename_map].dig("p1", "v")).to eq("left_v")
        expect(result[:rename_map].dig("p2", "v")).to eq("right_v")
      end
    end

    describe "unsafe author renamed_to" do
      let(:elements) do
        [
          el(id: "s1"),
          process_assign("seed", "v", "seed"),
          process_assign("overwrite", "v", "over", renamed_to: "1bad"),
          el(id: "e1", type: "end")
        ]
      end

      let(:connections) do
        [conn(from: "s1", to: "seed"), conn(from: "seed", to: "overwrite"), conn(from: "overwrite", to: "e1")]
      end

      it "does not fold an identifier that is not a safe target" do
        expect(result[:rename_map].dig("overwrite", "v")).to match(/\Av_[0-9a-f]{4}\z/)
      end
    end
  end

  # -----------------------------------------------------------------------
  # rename_map — no collisions (should be empty)
  # -----------------------------------------------------------------------
  describe "rename_map — no pin collisions" do
    let(:elements) { [el(id: "s1"), el(id: "e1", type: "end")] }
    let(:connections) { [conn(from: "s1", to: "e1")] }


    it "rename_map is empty when no pins collide" do
      # start and end elements produce no output pins via IoExtractor
      expect(result[:rename_map]).to be_empty
    end
  end

  describe "loop-carried variables" do
    let(:elements) do
      [el(id: "start"), el(id: "seed", type: "process"), el(id: "gap", type: "process"),
        el(id: "loop", type: "loop"), el(id: "reader", type: "process"), el(id: "writer", type: "process"), el(id: "end", type: "end")].tap do |nodes|
        %w[seed writer].each do |id|
          nodes.find { |node| node["id"] == id }["properties"] = { "steps" => [{
            "id" => id, "action" => "assign_value", "config" => { "resultVar" => "value", "valueType" => "string", "stringValue" => id }
          }] }
        end
      end
    end
    let(:connections) do
      [%w[start seed], %w[seed gap], %w[gap loop], %w[loop reader], %w[reader writer], %w[writer loop], %w[loop end]].map do |from, to|
        conn(from: from, to: to)
      end
    end

    it "excludes future body writes and the reader itself from first-iteration predecessors" do
      expect(result[:reachability]["reader"]).to contain_exactly("start", "seed", "gap", "loop")
      expect(result[:reachability]["loop"]).to contain_exactly("start", "seed", "gap")
      expect(result[:reachability]["end"]).to include("writer")
    end

    it "preserves producer snapshots and initializes a separate loop state slot from the seed" do
      expect(result[:rename_map].dig("seed", "value")).to be_nil
      expect(result[:rename_map].dig("writer", "value")).to eq("value_0b66")
      slot = result[:loop_body_slots].fetch("writer").fetch("value")
      expect(slot).not_to eq("value")
      expect(slot).to eq("_loop_loop_step_value")
      expect(slot).not_to match(/[0-9a-f]{64}/)
      source = result[:loop_initializers].fetch("loop").fetch(slot)
      expect(source).to include(pin: "value", candidates: ["seed:value"])
      expect(result[:loop_reads].fetch("reader").fetch("value")).to eq(slot)
      expect(result[:loop_reads].fetch("gap")).to be_empty
    end
  end

  # -----------------------------------------------------------------------
  # .merge_rename_map_into_overrides — class method
  # -----------------------------------------------------------------------
  describe ".merge_rename_map_into_overrides" do
    describe "when io_index has no rename entries for the element" do
      let(:element) { { "id" => "p1", "properties" => {} } }
      let(:io_index) { { rename_map: {} } }

      it "returns a hash with 'inputs' and 'outputs' keys" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result).to have_key("inputs")
        expect(result).to have_key("outputs")
      end

      it "outputs is an empty array when no overrides or renames exist" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result["outputs"]).to be_empty
      end
    end

    describe "when io_index has a rename entry for the element" do
      let(:element) { { "id" => "p1", "properties" => {} } }

      let(:io_index) do
        { rename_map: { "p1" => { "result" => "result_a1b2" } } }
      end

      it "adds the renamed pin to outputs" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result["outputs"]).to include({ "pin" => "result", "renamed_to" => "result_a1b2" })
      end
    end

    describe "when element already has an author-supplied output override for the same pin" do
      let(:element) do
        {
          "id" => "p1",
          "properties" => {
            "io_overrides" => {
              "inputs" => [],
              "outputs" => [{ "pin" => "result", "renamed_to" => "custom_name" }]
            }
          }
        }
      end

      let(:io_index) do
        { rename_map: { "p1" => { "result" => "result_auto" } } }
      end

      it "keeps the author-supplied override (explicit wins over implicit)" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        pinned = result["outputs"].select { |o| (o["pin"] || o[:pin]).to_s == "result" }
        expect(pinned.size).to eq(1)
        expect(pinned.first["renamed_to"]).to eq("custom_name")
      end
    end

    describe "when the author renamed_to is not a safe target" do
      let(:element) do
        {
          "id" => "overwrite",
          "properties" => {
            "io_overrides" => {
              "outputs" => [{ "pin" => "v", "renamed_to" => "1bad" }]
            }
          }
        }
      end

      let(:io_index) do
        { rename_map: { "overwrite" => { "v" => "v_3817" } } }
      end

      it "still applies the conflict-resolver rename so the writer does not clobber the seed" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result["outputs"]).to include({ "pin" => "v", "renamed_to" => "v_3817" })
      end
    end

    describe "when element has io_overrides with symbol keys" do
      let(:element) do
        {
          "id" => "p1",
          "properties" => {
            "io_overrides" => {
              inputs: [],
              outputs: []
            }
          }
        }
      end

      let(:io_index) do
        { rename_map: { "p1" => { "score" => "score_x9y2" } } }
      end

      it "handles symbol-keyed io_overrides and still applies renames" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result["outputs"]).to include({ "pin" => "score", "renamed_to" => "score_x9y2" })
      end
    end

    describe "when io_overrides is absent from properties" do
      let(:element) { { "id" => "p2", "properties" => {} } }
      let(:io_index) { { rename_map: { "p2" => { "data" => "data_1234" } } } }

      it "starts with empty inputs/outputs and applies the rename" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result["inputs"]).to be_empty
        expect(result["outputs"]).to include({ "pin" => "data", "renamed_to" => "data_1234" })
      end
    end

    describe "when element has no entry in rename_map" do
      let(:element) { { "id" => "p3", "properties" => {} } }
      let(:io_index) { { rename_map: {} } }

      it "returns empty outputs when nothing to rename" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        expect(result["outputs"]).to be_empty
      end
    end

    describe "multiple rename entries for the same element" do
      let(:element) { { "id" => "p1", "properties" => {} } }

      let(:io_index) do
        { rename_map: { "p1" => { "alpha" => "alpha_11aa", "beta" => "beta_22bb" } } }
      end

      it "adds all renamed pins to outputs" do
        result = described_class.merge_rename_map_into_overrides(element, io_index)
        pins = result["outputs"].map { |o| o["pin"] }
        expect(pins).to contain_exactly("alpha", "beta")
      end
    end
  end
end
