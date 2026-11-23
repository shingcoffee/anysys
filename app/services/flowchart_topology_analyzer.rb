# frozen_string_literal: true

# Analyzes the flowchart graph to identify Decision branch groups and their
# merge nodes. Used by ActivityGenerator's branch-aware DFS (visit each
# decision's branches before its merge).
class FlowchartTopologyAnalyzer
  BRANCHING_TYPES = %w[decision].freeze

  Result = Struct.new(:branch_groups, keyword_init: true)

  def initialize(elements, connections)
    @elements    = elements
    @connections = connections
    @element_map = elements.index_by { |el| el["id"] }
    @adjacency   = build_adjacency
  end

  def analyze
    branch_groups = {}

    branching_elements.each do |el|
      el_id     = el["id"]
      out_conns = outgoing_connections(el_id)

      branches = {}
      out_conns.each_with_index do |conn, i|
        branch_key = :"branch_#{i}"
        branches[branch_key] = {
          connection_id: conn["id"],
          label:         conn["label"] || branch_key.to_s,
          match_value:   conn["matchValue"]
        }
      end

      merge_id = out_conns.size >= 2 ? find_convergence_node(el_id, out_conns.map { |c| c["to"] }) : nil
      branch_groups[el_id] = {
        branches:      branches,
        merge_node_id: merge_id
      }
    end

    Result.new(branch_groups:)
  end

  private

  attr_reader :elements, :connections, :element_map, :adjacency

  def build_adjacency
    Hash.new { |h, k| h[k] = [] }.tap do |adj|
      connections.each { |c| adj[c["from"]] << c }
    end
  end

  def outgoing_connections(node_id)
    adjacency[node_id]
  end

  def branching_elements
    elements.select { |el| BRANCHING_TYPES.include?(el["type"]) }
  end

  def find_convergence_node(decision_id, start_ids)
    reachable_sets = start_ids.map { |id| bfs_reachable(id) }
    return nil if reachable_sets.empty?

    common = reachable_sets.reduce(:&)
    common -= Set.new([decision_id])
    return nil if common.empty?

    dfs_order_from(decision_id).find { |id| common.include?(id) }
  end

  def bfs_reachable(start_id)
    visited = Set.new
    queue   = [start_id]
    while (node_id = queue.shift)
      next if visited.include?(node_id)
      visited.add(node_id)
      adjacency[node_id].each { |conn| queue << conn["to"] }
    end
    visited
  end

  def dfs_order_from(start_id)
    visited = []
    seen    = Set.new
    dfs_visit_ordered(start_id, seen, visited)
    visited
  end

  def dfs_visit_ordered(node_id, seen, result)
    return if seen.include?(node_id)
    seen.add(node_id)
    result << node_id
    adjacency[node_id].each { |conn| dfs_visit_ordered(conn["to"], seen, result) }
  end
end
