# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::GraphBuilder do
  def build_el(id:, type: "process")
    { "id" => id, "type" => type, "label" => type.capitalize }
  end

  def build_conn(from:, to:)
    { "from" => from, "to" => to }
  end

  subject(:builder) { described_class.new(elements, connections).build }

  # Default graph: a linear start -> process -> end chain. Describes that need a
  # different topology override `elements`/`connections`.
  let(:elements) do
    [
      build_el(id: "s1", type: "start"),
      build_el(id: "p1", type: "process"),
      build_el(id: "e1", type: "end")
    ]
  end

  let(:connections) do
    [build_conn(from: "s1", to: "p1"), build_conn(from: "p1", to: "e1")]
  end

  # -----------------------------------------------------------------------
  # #build — element_map
  # -----------------------------------------------------------------------
  describe "#build — element_map" do
    it "indexes elements by id" do
      expect(builder.element_map.keys).to contain_exactly("s1", "p1", "e1")
    end

    it "stores the full element hash in element_map" do
      expect(builder.element_map["s1"]["type"]).to eq("start")
    end
  end

  # -----------------------------------------------------------------------
  # #build — adjacency
  # -----------------------------------------------------------------------
  describe "#build — adjacency" do
    it "builds outgoing adjacency list keyed by source id" do
      expect(builder.adjacency["s1"]).to eq(["p1"])
      expect(builder.adjacency["p1"]).to eq(["e1"])
    end

    it "returns an empty array for a node with no outgoing edges" do
      expect(builder.adjacency["e1"]).to eq([])
    end
  end

  # -----------------------------------------------------------------------
  # #start_node_id
  # -----------------------------------------------------------------------
  describe "#start_node_id" do
    it "returns the id of the start element" do
      builder = described_class.new(
        [build_el(id: "s1", type: "start"), build_el(id: "e1", type: "end")],
        []
      ).build
      expect(builder.start_node_id).to eq("s1")
    end

    it "returns nil when there is no start element" do
      builder = described_class.new([build_el(id: "p1", type: "process")], []).build
      expect(builder.start_node_id).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # #topological_order — linear chain
  # -----------------------------------------------------------------------
  describe "#topological_order — linear chain" do
    it "places the start element before downstream nodes" do
      order = builder.topological_order
      expect(order.index("s1")).to be < order.index("p1")
      expect(order.index("p1")).to be < order.index("e1")
    end

    it "returns all element ids" do
      expect(builder.topological_order).to contain_exactly("s1", "p1", "e1")
    end
  end

  # -----------------------------------------------------------------------
  # #topological_order — no connections (all nodes are sources)
  # -----------------------------------------------------------------------
  describe "#topological_order — no connections" do
    let(:elements) do
      [
        build_el(id: "a"),
        build_el(id: "b"),
        build_el(id: "c")
      ]
    end

    let(:connections) { [] }

    it "returns all elements (each is a zero-in-degree source)" do
      expect(builder.topological_order).to contain_exactly("a", "b", "c")
    end
  end

  # -----------------------------------------------------------------------
  # #topological_order — branching graph (decision)
  # -----------------------------------------------------------------------
  describe "#topological_order — branching graph" do
    # start -> process -> decision -> [yes_branch, no_branch] -> end
    let(:elements) do
      [
        build_el(id: "s1", type: "start"),
        build_el(id: "p1", type: "process"),
        build_el(id: "d1", type: "decision"),
        build_el(id: "p2", type: "process"),
        build_el(id: "p3", type: "process"),
        build_el(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_conn(from: "s1", to: "p1"),
        build_conn(from: "p1", to: "d1"),
        build_conn(from: "d1", to: "p2"),
        build_conn(from: "d1", to: "p3"),
        build_conn(from: "p2", to: "e1"),
        build_conn(from: "p3", to: "e1")
      ]
    end


    it "places start before process before decision" do
      order = builder.topological_order
      expect(order.index("s1")).to be < order.index("p1")
      expect(order.index("p1")).to be < order.index("d1")
    end

    it "places both branch nodes after the decision" do
      order = builder.topological_order
      expect(order.index("d1")).to be < order.index("p2")
      expect(order.index("d1")).to be < order.index("p3")
    end

    it "places end after all branch nodes" do
      order = builder.topological_order
      expect(order.index("p2")).to be < order.index("e1")
      expect(order.index("p3")).to be < order.index("e1")
    end

    it "includes all six elements" do
      expect(builder.topological_order).to contain_exactly("s1", "p1", "d1", "p2", "p3", "e1")
    end
  end

  # -----------------------------------------------------------------------
  # #topological_order — cycle (Kahn's algorithm returns partial order)
  # -----------------------------------------------------------------------
  describe "#topological_order — cyclic graph" do
    let(:elements) do
      [
        build_el(id: "s1", type: "start"),
        build_el(id: "p1", type: "process"),
        build_el(id: "p2", type: "process"),
        build_el(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_conn(from: "s1", to: "p1"),
        build_conn(from: "p1", to: "p2"),
        build_conn(from: "p2", to: "p1"),   # creates cycle
        build_conn(from: "p2", to: "e1")
      ]
    end


    it "returns fewer ids than total elements (cycle nodes are excluded)" do
      order = builder.topological_order
      expect(order.size).to be < elements.size
    end

    it "does not include both cyclic nodes in the order" do
      order = builder.topological_order
      # Kahn's algorithm cannot place both p1 and p2 when they form a cycle;
      # at least one must be absent from the topological order.
      both_present = order.include?("p1") && order.include?("p2")
      expect(both_present).to be false
    end
  end

  # -----------------------------------------------------------------------
  # #topological_order — disconnected components
  # -----------------------------------------------------------------------
  describe "#topological_order — disconnected components" do
    # Two independent chains: s1->e1 and a->b (island)
    let(:elements) do
      [
        build_el(id: "s1", type: "start"),
        build_el(id: "e1", type: "end"),
        build_el(id: "a"),
        build_el(id: "b")
      ]
    end

    let(:connections) do
      [
        build_conn(from: "s1", to: "e1"),
        build_conn(from: "a", to: "b")
      ]
    end


    it "includes all elements from both components" do
      expect(builder.topological_order).to contain_exactly("s1", "e1", "a", "b")
    end

    it "preserves order within each component" do
      order = builder.topological_order
      expect(order.index("s1")).to be < order.index("e1")
      expect(order.index("a")).to be < order.index("b")
    end
  end

  # -----------------------------------------------------------------------
  # Connections referencing unknown element ids are silently ignored
  # -----------------------------------------------------------------------
  describe "connections with unknown element ids" do
    let(:elements) do
      [
        build_el(id: "s1", type: "start"),
        build_el(id: "e1", type: "end")
      ]
    end

    let(:connections) do
      [
        build_conn(from: "s1", to: "e1"),
        build_conn(from: "GHOST", to: "e1")   # unknown from
      ]
    end


    it "silently ignores connections whose 'from' id is not in element_map" do
      # Kahn still processes s1 and e1 correctly
      expect(builder.topological_order).to contain_exactly("s1", "e1")
    end
  end
end
