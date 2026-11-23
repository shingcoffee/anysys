# frozen_string_literal: true

class ActivityDiagramGenerator
  # The compiled flow as drawable nodes and edges. Failure edges (and the
  # Failure terminal they lead to) are hidden unless asked for: every step can
  # fail the same way, so drawing them all buries the designed path.
  class Graph
    Node = Data.define(:id, :kind, :label)
    Edge = Data.define(:from, :to, :label, :failure)

    KINDS = %i[start step decision loop subflow end failure].freeze

    attr_reader :nodes, :edges

    def initialize(nodes:, edges:)
      @nodes = nodes
      @edges = edges
    end

    def failure_paths?
      edges.any?(&:failure)
    end

    # Node kinds on the designed path, in legend order.
    def kinds
      visible_nodes(false).map(&:kind).uniq.sort_by { |kind| KINDS.index(kind) }
    end

    def to_mermaid(failure_paths: false)
      MermaidRenderer.new(visible_nodes(failure_paths), visible_edges(failure_paths)).render
    end

    private

    def visible_nodes(failure_paths)
      failure_paths ? nodes : nodes.reject { |node| node.kind == :failure }
    end

    def visible_edges(failure_paths)
      failure_paths ? edges : edges.reject(&:failure)
    end
  end
end
