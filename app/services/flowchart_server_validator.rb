# frozen_string_literal: true

require "timeout"

# Server-side validation for the flowchart editor's Validate button.
# Runs the checks only the server can perform against the SUBMITTED
# (possibly unsaved) canvas configuration:
#   - subflow existence/accessibility (tenant-scoped, no existence leak)
#   - subflow reference cycles (including self-reference)
#   - ActivityGenerator dry-run (structure failures, TODO markers, timeout)
#
# Returns an array of problem hashes:
#   { type:, severity:, element_id:, connection_id:, message:, fix_hint: }
class FlowchartServerValidator
  DRY_RUN_TIMEOUT_SECONDS = 10

  # Cheap pre-flight cap: payloads beyond these sizes skip server-side checks
  # entirely instead of burning the timeout budget on unbounded input.
  MAX_ELEMENTS = 1_000
  MAX_CONNECTIONS = 5_000

  def initialize(flowchart, configuration)
    @flowchart = flowchart
    @configuration = configuration || {}
  end

  def call
    elements = Array(@configuration["elements"])
    return [] if elements.empty?
    return [payload_too_large_problem] if payload_too_large?(elements)

    # The timeout covers BOTH phases — the subflow walk traverses persisted
    # configurations and is just as unbounded as the codegen dry-run.
    Timeout.timeout(DRY_RUN_TIMEOUT_SECONDS) do
      apply_submitted_configuration!

      problems = subflow_validator.call(elements) +
                 config_validator.call(elements, Array(@configuration["connections"]))
      # The dry run only means something on an otherwise valid graph.
      next problems if problems.any? { |problem| problem[:severity] == "error" }

      problems + codegen_validator.call(@flowchart)
    end
  rescue Timeout::Error
    [validation_timeout_problem]
  end

  private

  def payload_too_large?(elements)
    elements.size > MAX_ELEMENTS ||
      Array(@configuration["connections"]).size > MAX_CONNECTIONS
  end

  def payload_too_large_problem
    problem(
      type: "server_check_unavailable",
      severity: "warning",
      message: I18n.t("maint_core.flowcharts.server_validation.payload_too_large")
    )
  end

  def validation_timeout_problem
    problem(
      type: "codegen_check_timeout",
      severity: "warning",
      message: I18n.t("maint_core.flowcharts.server_validation.check_timeout", seconds: DRY_RUN_TIMEOUT_SECONDS)
    )
  end

  # Work on an in-memory copy: same tenant context, submitted config,
  # never saved. JsonSerializable memoizes the parsed configuration, and a
  # plain attribute write does not invalidate that memo — so also go through
  # the concern's setter, which re-assigns the identical serialized value AND
  # flushes the memo so #elements/#connections reflect the submitted state.
  def apply_submitted_configuration!
    @flowchart.assign_attributes(configuration: @configuration.to_json)
    @flowchart.configuration_json = @configuration
  end

  def subflow_validator
    @subflow_validator ||= SubflowValidator.new(@flowchart)
  end

  def config_validator
    @config_validator ||= ConfigValidator.new
  end

  def codegen_validator
    @codegen_validator ||= CodegenValidator.new
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

require_relative "flowchart_server_validator/subflow_validator"
require_relative "flowchart_server_validator/config_validator"
require_relative "flowchart_server_validator/codegen_validator"
