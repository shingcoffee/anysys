# frozen_string_literal: true

class ActivityGenerator
  # Builds the graph data structures (element map, adjacency list) and computes
  # the topological ordering of elements using Kahn's algorithm.
  #
  # Kept separate from the DFS traversal (which depends on topology analysis,
  # subprocess detection, and name derivation) to give it a single clear job.
  class GraphBuilder
    attr_reader :element_map, :adjacency

    # @param elements    [Array<Hash>]
    # @param connections [Array<Hash>]
    def initialize(elements, connections)
      @elements    = elements
      @connections = connections
    end

    # Build element_map and adjacency from the raw element/connection arrays.
    # @return [self]
    def build
      @element_map = @elements.index_by { |el| el["id"] }
      @adjacency   = Hash.new { |h, k| h[k] = [] }
      @connections.each { |c| @adjacency[c["from"]] << c["to"] }
      self
    end

    # @return [String, nil] id of the Start element, or nil if absent
    def start_node_id
      @elements.find { |el| el["type"] == "start" }&.dig("id")
    end

    # Build topological order using Kahn's algorithm. Returns array of element
    # IDs from start to end (sources first). Used by ConflictResolver to
    # determine which element is the "first emitter" of a colliding pin.
    #
    # NOTE: do NOT use `Hash.new(0)` here. With a default-0 hash, the
    # `in_degree[id] ||= 0` initializer never assigns (0 is truthy) and
    # `in_degree.key?(id)` reports false for every element, which silently
    # collapsed the original implementation to "always returns []".
    def topological_order
      in_degree = {}
      adj = Hash.new { |h, k| h[k] = [] }

      @elements.each { |el| in_degree[el["id"]] = 0 }
      @connections.each do |c|
        from_id = c["from"]
        to_id   = c["to"]
        next unless in_degree.key?(from_id) && in_degree.key?(to_id)
        adj[from_id] << to_id
        in_degree[to_id] += 1
      end

      queue = in_degree.select { |_id, deg| deg == 0 }.keys
      order = []

      until queue.empty?
        cur = queue.shift
        order << cur
        adj[cur].each do |neighbor|
          in_degree[neighbor] -= 1
          queue << neighbor if in_degree[neighbor] == 0
        end
      end

      order
    end
  end
end
