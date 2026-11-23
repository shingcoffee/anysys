# frozen_string_literal: true

class ActivityGenerator
  # Walks the flowchart from Start in Railway declaration order. Every branch
  # of a decision comes before the node the branches merge into, and a loop's
  # body before its exit, so branch steps are declared before merge steps.
  # Start and response-less Ends produce no step.
  class StepCollector
    def initialize(elements:, loop_topology:, name_deriver:, subflow_resolver:)
      @elements = elements
      @loop_topology = loop_topology
      @name_deriver = name_deriver
      @subflow_resolver = subflow_resolver
    end

    # @return [Array<Step>]
    def call
      connections = @loop_topology.routing_connections
      graph = GraphBuilder.new(@elements, connections).build
      return [] unless (start_id = graph.start_node_id)

      @element_map = graph.element_map
      @adjacency = graph.adjacency
      @branch_groups = FlowchartTopologyAnalyzer.new(@elements, connections).analyze.branch_groups
      @used_names = {}
      @steps = []
      visit(start_id, Set.new)
      @steps
    end

    private

    def visit(node_id, visited, stop_at: nil)
      return if visited.include?(node_id) || node_id == stop_at

      visited.add(node_id)
      element = @element_map[node_id]
      collect(element) if element

      region = element && @loop_topology.regions[node_id]
      merge_id = element && @branch_groups.dig(node_id, :merge_node_id)
      if region&.dig(:head_id)
        visit(region[:head_id], visited)
        visit(region[:exit_id], visited, stop_at: stop_at)
      elsif merge_id
        @adjacency[node_id].each { |child_id| visit(child_id, visited, stop_at: merge_id) }
        visit(merge_id, visited, stop_at: stop_at)
      else
        @adjacency[node_id].each { |child_id| visit(child_id, visited, stop_at: stop_at) }
      end
    end

    def collect(element)
      return if element["type"] == "start" || ActivityGenerator.stepless_end?(element)

      subprocess = subprocess_for(element) if element["type"] == "subflow"
      @steps << Step.new(
        element: element,
        method_name: @name_deriver.derive_method_name(element, @used_names),
        subprocess: subprocess,
        magnetic: true,
        outputs: []
      )
    end

    def subprocess_for(element)
      subprocess = @subflow_resolver.resolve!(element)
      return unless subprocess

      mapping = CodeGenerators::ElementTypes::Subflow::SubflowGenerator.new(element, {}).variable_mapping
      subprocess.merge(variable_mapping: mapping)
    end
  end
end
