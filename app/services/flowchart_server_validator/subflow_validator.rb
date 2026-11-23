# frozen_string_literal: true

class FlowchartServerValidator
  # Validates all subflow elements in the submitted configuration:
  #   - tenant-scoped accessibility check (no existence leak across tenants)
  #   - reference-cycle detection via DFS over persisted configurations
  class SubflowValidator
    def initialize(flowchart)
      @subflows = ActivityGenerator::SubflowResolver.new(flowchart)
    end

    # Cycles follow each referenced flowchart's persisted configuration.
    def call(elements)
      elements.filter_map do |el|
        next unless el.is_a?(Hash) && el["type"] == "subflow"

        target_id = el.dig("properties", "flowchartId").presence
        next if target_id.blank?

        if @subflows.find(target_id).nil?
          inaccessible_problem(el)
        elsif @subflows.cycle?(target_id)
          cycle_problem(el)
        end
      end
    end

    private

    # Deliberately identical for "id does not exist" and "id belongs to another
    # tenant" — the message must not leak cross-tenant existence.
    def inaccessible_problem(element)
      problem(
        type: "subflow_inaccessible",
        severity: "error",
        element_id: element["id"],
        message: I18n.t("maint_core.flowcharts.server_validation.subflow_inaccessible", label: element["label"]),
        fix_hint: I18n.t("maint_core.flowcharts.editor.fix_hints.select_accessible_flowchart")
      )
    end

    def cycle_problem(element)
      problem(
        type: "subflow_cycle",
        severity: "error",
        element_id: element["id"],
        message: I18n.t("maint_core.flowcharts.server_validation.subflow_cycle", label: element["label"]),
        fix_hint: I18n.t("maint_core.flowcharts.editor.fix_hints.remove_circular_subflow")
      )
    end

    def problem(type:, severity:, message:, element_id: nil, connection_id: nil, fix_hint: nil)
      {
        type: type,
        severity: severity,
        element_id: element_id,
        connection_id: connection_id,
        message: message,
        fix_hint: fix_hint
      }
    end
  end
end
