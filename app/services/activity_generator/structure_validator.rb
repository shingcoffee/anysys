# frozen_string_literal: true

class ActivityGenerator
  # Validates a flowchart's structural integrity before code generation.
  # Checks for required elements, dangling connections, unreachable nodes,
  # and cycles. Returns an array of human-readable error strings (empty = valid).
  class StructureValidator
    UNSUPPORTED_STRUCTURAL_TYPES = %w[
      fork join parallel_for_each saga signal_wait transaction switch timer
    ].freeze
    MULTI_OUTGOING_EXEMPT_TYPES = %w[decision loop].freeze

    # @param elements    [Array<Hash>]
    # @param connections [Array<Hash>]
    # @param topological_order_provider [#call] callable that returns the
    #   Kahn topological order array (injected to avoid duplicating that logic)
    # @param flowchart [Flowchart, nil] parent flowchart (class-name collision check)
    # @param subflow_lookup [#call, nil] `(id) -> flowchart` for subflow targets.
    #   Collision check runs only when both flowchart and subflow_lookup are given.
    def initialize(elements, connections, topological_order_provider:, flowchart: nil, subflow_lookup: nil)
      @elements = elements
      @connections = connections
      @topological_order_provider = topological_order_provider
      @flowchart = flowchart
      @subflow_lookup = subflow_lookup
    end

    # @return [Array<String>] validation error messages (empty when valid)
    def call
      errors = []
      start_elements = @elements.select { |el| el["type"] == "start" }
      end_elements   = @elements.select { |el| el["type"] == "end" }
      element_ids    = @elements.to_set { |el| el["id"] }

      errors << I18n.t("maint_core.flowcharts.structure_errors.missing_start") if start_elements.empty?
      errors << I18n.t("maint_core.flowcharts.structure_errors.multiple_starts") if start_elements.length > 1
      errors << I18n.t("maint_core.flowcharts.structure_errors.missing_end") if end_elements.empty?

      @elements.each do |el|
        if UNSUPPORTED_STRUCTURAL_TYPES.include?(el["type"])
          errors << I18n.t("maint_core.flowcharts.structure_errors.unsupported_type", label: el["label"], type: el["type"])
        end
        if el["type"] == "decision" &&
           @connections.count { |connection| connection["from"] == el["id"] } < 2
          errors << I18n.t("maint_core.flowcharts.structure_errors.decision_branches", label: el["label"])
        end
        if el["type"] == "end" && @connections.any? { |connection| connection["from"] == el["id"] }
          errors << I18n.t("maint_core.flowcharts.structure_errors.end_outgoing", label: el["label"])
        end
        if el["type"] == "process" && process_steps(el).size > 1
          errors << I18n.t("maint_core.flowcharts.structure_errors.process_multiple_actions", label: el["label"])
        end
        if !MULTI_OUTGOING_EXEMPT_TYPES.include?(el["type"]) &&
           @connections.count { |connection| connection["from"] == el["id"] } > 1
          errors << I18n.t("maint_core.flowcharts.structure_errors.multiple_outgoing", label: el["label"])
        end
      end

      # Dangling connections
      @connections.each do |c|
        errors << I18n.t("maint_core.flowcharts.structure_errors.connection_from_unknown", id: c["from"]) unless element_ids.include?(c["from"])
        errors << I18n.t("maint_core.flowcharts.structure_errors.connection_to_unknown", id: c["to"]) unless element_ids.include?(c["to"])
      end

      # Every non-start element must have an incoming connection
      @elements.each do |el|
        next if el["type"] == "start"
        has_incoming = @connections.any? { |c| c["to"] == el["id"] }
        errors << I18n.t("maint_core.flowcharts.structure_errors.no_incoming", label: el["label"]) unless has_incoming
      end

      # Reachability from Start
      if start_elements.length == 1
        reachable = compute_reachable_ids(start_elements.first["id"])
        @elements.each do |el|
          next if el["type"] == "start"
          next if reachable.include?(el["id"])
          errors << I18n.t("maint_core.flowcharts.structure_errors.unreachable", label: el["label"])
        end
      end

      # Cycle detection via Kahn's topological sort
      topo = @topological_order_provider.call
      if topo.size != @elements.size
        cyclic = element_ids - topo.to_set
        errors << I18n.t("maint_core.flowcharts.structure_errors.cycle", ids: cyclic.sort.join(", "))
      end

      errors.concat(class_name_collision_errors)

      errors
    end

    private

    def process_steps(element)
      properties = element["properties"]
      if properties.is_a?(Hash) && properties["steps"].is_a?(Array)
        properties["steps"]
      elsif element["steps"].is_a?(Array)
        element["steps"]
      else
        []
      end
    end

    def class_name_collision_errors
      return [] unless @flowchart && @subflow_lookup

      names = NameDeriver.new
      parent_class = names.derive_activity_class_name(@flowchart.name)
      seen = {}
      reported = {}

      @elements.each_with_object([]) do |element, errors|
        next unless element["type"] == "subflow"

        target = resolve_subflow(element.dig("properties", "flowchartId"))
        next unless target

        child_class = names.derive_activity_class_name(target.name)
        parent_collision = child_class == parent_class
        sibling_collision = seen.key?(child_class) && seen[child_class] != target.id
        if (parent_collision || sibling_collision) && !reported[child_class]
          reported[child_class] = true
          errors << I18n.t("maint_core.flowcharts.structure_errors.class_name_collision", name: child_class)
        end
        seen[child_class] ||= target.id
      end
    end

    def resolve_subflow(flowchart_id)
      return if flowchart_id.blank?

      @subflow_lookup.call(flowchart_id)
    end

    # Forward BFS from root_id to find all reachable element ids.
    def compute_reachable_ids(root_id)
      adj = Hash.new { |h, k| h[k] = [] }
      @connections.each { |c| adj[c["from"]] << c["to"] }

      reachable = Set.new([root_id])
      queue = [root_id]
      until queue.empty?
        node = queue.shift
        adj[node].each do |child|
          next if reachable.include?(child)
          reachable << child
          queue << child
        end
      end
      reachable
    end
  end
end
