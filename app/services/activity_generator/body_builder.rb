# frozen_string_literal: true

class ActivityGenerator
  # Writes the instance method behind each Railway step. Element types with a
  # generator (decision, loop, …) produce the body themselves; a process box
  # runs its step action's generator. Bodies are then rewritten for element
  # I/O (renamed outputs, loop state) and wrapped to the house line width.
  class BodyBuilder
    # Element types whose behaviour is defined entirely by their step actions.
    STEP_CONTAINER_ELEMENT_TYPES = %w[process start end].freeze

    # @param outgoing [#call] element id -> outgoing connections in port order
    # @param steps [Array<Step>] bound steps; empty while validating up front
    # @param element_io [Hash, nil] ElementIoIndex result
    def initialize(bound_entity:, outgoing:, steps: [], element_io: nil, registry: CodeGenerators::GeneratorRegistry.instance)
      @base_context = { bound_entity: bound_entity }
      @outgoing = outgoing
      @steps = steps.index_by(&:element_id)
      @element_io = element_io
      @registry = registry
    end

    # Rejects an element's invalid configuration before any source exists.
    def validate_element!(element)
      generator_class = @registry.find_element_type(element["type"])
      return unless generator_class

      validate!(generator_class.new(element, context_for(element)), element.fetch("properties", {}),
        element_id: element["id"], element_type: element["type"])
    end

    def method_source(step)
      label = ActivityGenerator.safe_comment_text(step.element["label"])
      source = [
        ("# #{label}" if label.present?),
        "def #{step.method_name}(ctx, **)",
        body(step.element).indent(2),
        "end"
      ].compact.join("\n")
      CodeGenerators::SourceFormatter.call(source, max_width: CodeGenerators::SourceFormatter::STEP_WIDTH)
    end

    private

    def body(element)
      type = element["type"]
      generator_class = @registry.find_element_type(type)
      if generator_class
        result = generator_class.new(element, context_for(element)).generate_body
        return rewrite(element, result) if result
      elsif !STEP_CONTAINER_ELEMENT_TYPES.include?(type)
        raise Error.new(
          code: :unknown_element_type,
          message: I18n.t("maint_core.flowcharts.structure_errors.unknown_element_type", type: type.inspect),
          element_id: element["id"],
          element_type: type
        )
      end

      rewrite(element, process_body(element))
    end

    def process_body(element)
      actions = element.dig("properties", "steps") || []
      return "true" if actions.empty?

      codes = actions.map { |action| action_code(action, element_id: element["id"]) }
      return codes.compact.join("\n") unless codes.all?(&:nil?)

      comments = actions.map do |action|
        name = action["action"] || "operation"
        detail = action["selectionLabels"]&.join(" > ") || action["description"] || ""
        "# #{ActivityGenerator.safe_comment_text(detail.present? ? "#{name}: #{detail}" : name)}"
      end
      "#{comments.join("\n")}\n\ntrue"
    end

    def action_code(action_step, element_id:)
      action = action_step["action"]
      return if action.blank?

      generator_class = @registry.find_step_action(action)
      unless generator_class
        raise Error.new(
          code: :unknown_step_action,
          message: I18n.t("maint_core.flowcharts.structure_errors.unknown_step_action", action: action.inspect),
          element_id: element_id,
          action: action
        )
      end

      generator = generator_class.new(action_step, @base_context)
      validate!(generator, action_step.fetch("config", {}), element_id: element_id, action: action)
      generator.generate_body
    end

    def rewrite(element, body)
      return body unless @element_io

      ElementBodyRewriter.new(@element_io).call(element, body)
    end

    def context_for(element)
      step = @steps[element["id"]]
      case element["type"]
      when "decision"
        @base_context.merge(flowchart_topology: { outgoing_branches: decision_branches(element, step) })
      when "loop"
        @base_context.merge(
          done_signal: step&.done_signal,
          loop_state_key: step ? "_#{step.method_name}" : "_loop",
          loop_has_body: step&.body_id.present?,
          loop_execution: @element_io && @element_io[:loop_execution],
          loop_initializers: @element_io&.dig(:loop_initializers, element["id"]) || {},
          loop_exports: @element_io&.dig(:loop_exports, element["id"]) || {}
        )
      else
        @base_context
      end
    end

    # Bound branches once the step exists; a preview while validating.
    def decision_branches(element, step)
      return NameDeriver.outgoing_branches(element, @outgoing.call(element["id"])) unless step&.branches

      step.branches.map do |branch|
        { "signal" => branch[:signal], "semantic" => branch[:semantic].to_s, "matchValue" => branch[:match_value] }
      end
    end

    def validate!(generator, raw_config, element_id: nil, element_type: nil, action: nil)
      errors = generator.validate_config(raw_config)
      return if errors.empty?

      raise Error.new(
        code: :invalid_generator_config,
        message: I18n.t("code_generator_validation.invalid_configuration", errors: errors.join("; ")),
        element_id: element_id,
        element_type: element_type,
        action: action,
        details: errors
      )
    end
  end
end
