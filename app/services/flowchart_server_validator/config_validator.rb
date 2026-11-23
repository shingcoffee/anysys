# frozen_string_literal: true

class FlowchartServerValidator
  # Activates the dormant validate_config(cfg) method on every registered
  # generator. Mirrors the resolution logic in ActivityGenerator#method_body
  # and ActivityGenerator#generate_step_code exactly:
  #   - process elements: iterate steps; resolve via find_step_action
  #   - other element types: resolve via find_element_type
  # Unknown actions/types are skipped here and reported by the codegen dry-run.
  # Any exception from a generator is rescued and that item is silently
  # skipped so a buggy generator cannot abort validation.
  class ConfigValidator
    def call(elements, connections = [])
      registry = CodeGenerators::GeneratorRegistry.instance
      problems = []
      topology_elements = elements.select { |element| element.is_a?(Hash) }
      @topology_connections = connections.select { |connection| connection.is_a?(Hash) }
      @topology = FlowchartTopologyAnalyzer.new(topology_elements, @topology_connections).analyze

      elements.each do |el|
        next unless el.is_a?(Hash)

        if el["type"] == "process"
          problems.concat(process_problems(el, registry))
        else
          problems.concat(element_problems(el, registry))
        end
      end

      problems
    end

    private

    def process_problems(el, registry)
      steps = el.dig("properties", "steps") || []
      problems = []

      steps.each do |step|
        action = step["action"]
        next if action.blank?

        begin
          gen_class = registry.find_step_action(action)
          next if gen_class.nil?

          safe_step = with_hash_config(step, "config")
          errors = gen_class.new(safe_step, {}).validate_config(
            safe_step["config"].with_indifferent_access
          )
          action_label = FlowchartDefinitions::ActionLabel.for(action)
          step_label = step["label"].presence || el["label"].presence || action_label

          Array(errors).each do |err|
            problems << problem(
              type: "step_config_invalid",
              severity: "error",
              element_id: el["id"],
              field: err.respond_to?(:field) ? err.field : nil,
              message: I18n.t(
                "maint_core.flowcharts.config_problems.step_invalid",
                step: step_label,
                action: action_label,
                error: err
              ),
              fix_hint: I18n.t("maint_core.flowcharts.config_problems.fix_step")
            )
          end
        rescue Timeout::Error
          raise
        rescue StandardError
          # A buggy generator constructor or validate_config must not abort
          # the whole validation pass — skip this step silently.
          next
        end
      end

      problems
    end

    def element_problems(el, registry)
      begin
        gen_class = registry.find_element_type(el["type"])
        return [] if gen_class.nil?

        safe_el = with_hash_config(el, "properties")
        errors = gen_class.new(safe_el, generator_context(safe_el)).validate_config(
          safe_el["properties"].with_indifferent_access
        )

        Array(errors).map do |err|
          problem(
            type: "element_config_invalid",
            severity: "error",
            element_id: el["id"],
            field: err.respond_to?(:field) ? err.field : nil,
            message: I18n.t(
              "maint_core.flowcharts.config_problems.element_invalid",
              label: el["label"],
              type: element_type_label(el["type"]),
              error: err
            ),
            fix_hint: I18n.t("maint_core.flowcharts.config_problems.fix_element")
          )
        end

      rescue Timeout::Error
        raise
      rescue StandardError
        []
      end
    end

    def element_type_label(type)
      key = "flowchart_elements.#{type}.label"
      I18n.exists?(key) ? I18n.t(key) : type
    end

    def generator_context(element)
      return {} unless element["type"] == "decision"

      connections = Array(@topology_connections).select { |connection| connection["from"] == element["id"] }
      outgoing_branches = ActivityGenerator::NameDeriver.outgoing_branches(element, connections)
      { flowchart_topology: { outgoing_branches: outgoing_branches } }
    end

    # Generators read their config both in their constructor AND in
    # #validate_config. Arbitrary submitted JSON could carry a non-Hash config
    # (e.g. an array or string); both reads would then raise and the per-item
    # rescue would silently skip the check. Coerce a non-Hash config to {} on a
    # shallow copy so validate_config still runs and can report missing fields.
    def with_hash_config(item, config_key)
      return item if item[config_key].is_a?(Hash)

      item.merge(config_key => {})
    end

    def problem(type:, severity:, message:, element_id: nil, connection_id: nil, field: nil, fix_hint: nil)
      {
        type: type,
        severity: severity,
        element_id: element_id,
        connection_id: connection_id,
        field: field,
        message: message,
        fix_hint: fix_hint
      }
    end
  end
end
