# frozen_string_literal: true

class ActivityGenerator
  # Resolves the flowcharts a parent may embed as a Subprocess: its own
  # customer's flowcharts and shared ones (a shared parent sees only shared
  # ones). Anything else resolves to nil, indistinguishable from a missing id,
  # so references never reveal another tenant's flowcharts.
  class SubflowResolver
    # Reference chains deeper than this count as cycles.
    MAX_DEPTH = 32

    def self.visible_to(parent, flowchart_id)
      candidate = Flowchart.find_by(id: flowchart_id)
      return unless candidate
      return candidate if candidate.shared?

      candidate if parent.customer_id && candidate.customer_id == parent.customer_id
    end

    # +finder+ maps a flowchartId to the record to embed, or nil. Runtime
    # execution swaps in one that only accepts launched flowcharts.
    def initialize(parent, finder: nil)
      @parent = parent
      @finder = finder || ->(flowchart_id) { self.class.visible_to(parent, flowchart_id) }
      @found = {}
      @acyclic = Set.new
    end

    def find(flowchart_id)
      return if flowchart_id.blank?

      key = flowchart_id.to_s
      @found.fetch(key) { @found[key] = @finder.call(flowchart_id) }
    end

    # Whether following subflow references from +flowchart_id+ leads back to
    # the parent or round any loop below it — either would recurse forever at
    # runtime. Unresolvable references end the walk.
    def cycle?(flowchart_id, path = Set.new, depth = 0)
      key = flowchart_id.to_s
      return true if depth >= MAX_DEPTH || path.include?(key)
      return true if parent_id.present? && key == parent_id.to_s
      return false if @acyclic.include?(key)

      target = find(flowchart_id)
      return false unless target

      path.add(key)
      cyclic = subflow_ids(target).any? { |id| cycle?(id, path, depth + 1) }
      path.delete(key)
      @acyclic.add(key) unless cyclic
      cyclic
    end

    # Subprocess metadata for a subflow element; raises when its target cannot
    # be embedded.
    def resolve!(element)
      flowchart_id = element.dig("properties", "flowchartId")
      return if flowchart_id.blank?

      target = find(flowchart_id)
      raise reference_error(:invalid_subflow_reference, "subflow_inaccessible", element, flowchart_id) unless target
      raise reference_error(:subflow_cycle, "subflow_cycle", element, flowchart_id) if cycle?(target.id)

      {
        flowchart_id: target.id,
        activity_class_name: NameDeriver.new.derive_activity_class_name(target.name),
        subflow_name: target.name
      }
    end

    private

    def parent_id
      @parent.id if @parent.respond_to?(:id)
    end

    def subflow_ids(flowchart)
      Array(flowchart.elements).filter_map do |element|
        element.dig("properties", "flowchartId").presence if element.is_a?(Hash) && element["type"] == "subflow"
      end
    end

    def reference_error(code, message_key, element, flowchart_id)
      Error.new(
        code: code,
        message: I18n.t("maint_core.flowcharts.structure_errors.#{message_key}"),
        element_id: element["id"],
        element_type: "subflow",
        details: ["flowchartId=#{flowchart_id}"]
      )
    end
  end
end
