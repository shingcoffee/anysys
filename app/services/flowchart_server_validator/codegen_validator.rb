# frozen_string_literal: true

class FlowchartServerValidator
  # Performs the ActivityGenerator dry-run against the submitted (in-memory)
  # flowchart configuration, surfacing structure failures and generation errors.
  class CodegenValidator
    def call(flowchart)
      generator = ActivityGenerator.new(flowchart)

      structure_messages = generator.structure_errors
      return structure_failure_problems(structure_messages) if structure_messages.any?

      code = generator.generate
      return [generation_returned_nothing_problem] if code.nil?

      []
    rescue Timeout::Error
      # Re-raise so the outer FlowchartServerValidator#call guard produces
      # the single codegen_check_timeout warning.
      raise
    rescue ActivityGenerator::Error => e
      [
        problem(
          type: "codegen_failed",
          severity: "error",
          element_id: e.element_id,
          message: I18n.t("maint_core.flowcharts.server_validation.codegen_failed", code: e.code),
          fix_hint: I18n.t("maint_core.flowcharts.server_validation.review_configuration")
        )
      ]
    rescue StandardError => e
      # Exception class only — generator messages can embed user content.
      [
        problem(
          type: "codegen_failed",
          severity: "error",
          message: I18n.t("maint_core.flowcharts.server_validation.codegen_raised", error_class: e.class),
          fix_hint: I18n.t("maint_core.flowcharts.server_validation.review_configuration")
        )
      ]
    end

    private

    def structure_failure_problems(messages)
      messages.map do |message|
        problem(
          type: "codegen_failed",
          severity: "error",
          message: I18n.t("maint_core.flowcharts.server_validation.codegen_would_fail", message: message),
          fix_hint: I18n.t("maint_core.flowcharts.server_validation.fix_structure")
        )
      end
    end

    def generation_returned_nothing_problem
      problem(
        type: "codegen_failed",
        severity: "error",
        message: I18n.t("maint_core.flowcharts.server_validation.codegen_empty"),
        fix_hint: I18n.t("maint_core.flowcharts.server_validation.ensure_structure")
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
