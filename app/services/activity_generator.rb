# frozen_string_literal: true

# ActivityGenerator
#
# Compiles a Flowchart into the Ruby source of a Trailblazer::Activity::Railway.
#
#   1. StructureValidator / LoopTopology reject graphs that cannot compile.
#   2. Every element generator validates its configuration up front.
#   3. ElementIoIndex resolves which writer each element reads.
#   4. StepCollector orders the steps; decisions and loops get Routes signals.
#   5. WiringPlanner decides each step's magnetic/output wiring.
#   6. BodyBuilder writes each step method; ClassRenderer lays out the class.
#
# @example
#   ActivityGenerator.new(flowchart).generate
#   # => "# frozen_string_literal: true\n...class CreateUserActivity < Trailblazer::Activity::Railway\n  ..."
#
class ActivityGenerator
  include Loggable

  class Error < StandardError
    attr_reader :code, :element_id, :element_type, :action, :details

    def initialize(code:, message:, element_id: nil, element_type: nil, action: nil, details: [])
      @code = code
      @element_id = element_id
      @element_type = element_type
      @action = action
      @details = Array(details)
      super(message)
    end

    def to_h
      {
        code: code,
        message: message,
        element_id: element_id,
        element_type: element_type,
        action: action,
        details: details
      }.compact
    end
  end

  def self.safe_comment_text(text)
    sanitized = text.to_s.gsub(/[\r\n\t\x00-\x1F\x7F\u2028\u2029\u202A-\u202E\u2066-\u2069]+/, " ").strip
    sanitized.length > 200 ? "#{sanitized[0, 197]}..." : sanitized
  end

  # An End that writes no response compiles to the Railway's End.success
  # instead of a step.
  def self.stepless_end?(element)
    element["type"] == "end" && (element.dig("properties", "responseType").presence || "none") == "none"
  end

  attr_reader :flowchart, :elements, :connections, :bound_entity

  # +entity+ checks the steps' attribute references against one entity (see
  # Flowcharts::Compatibility). Without it the activity is entity-agnostic:
  # the submitting page supplies ctx[:bound_entity] at runtime.
  def initialize(flowchart, entity: nil)
    @flowchart = flowchart
    @elements = flowchart.elements || []
    @connections = flowchart.connections || []
    @bound_entity = entity
    @name_deriver = NameDeriver.new
  end

  def generate
    return nil if flowchart.name.blank? || elements.empty?
    return nil unless structure_valid?

    validator = BodyBuilder.new(bound_entity: bound_entity, outgoing: method(:outgoing_connections))
    elements.each { |element| validator.validate_element!(element) }
    element_io = build_element_io_index
    steps = StepCollector.new(
      elements: elements,
      loop_topology: loop_topology,
      name_deriver: @name_deriver,
      subflow_resolver: subflow_resolver
    ).call
    bind_routes(steps)
    plan = plan_wiring(steps)

    builder = BodyBuilder.new(bound_entity: bound_entity, outgoing: method(:outgoing_connections),
      steps: steps, element_io: element_io)
    activity_class = ClassRenderer.new(
      class_name: activity_class_name,
      steps: steps,
      canvas: canvas(steps, plan),
      method_sources: steps.reject(&:subprocess).map { |step| builder.method_source(step) }
    ).render
    [header(steps), activity_class].join("\n")
  end

  # Why the graph cannot compile, as human-readable messages (empty when it
  # can). FlowchartServerValidator reports these instead of a nil #generate.
  def structure_errors
    StructureValidator.new(
      elements,
      connections,
      topological_order_provider: method(:build_topological_order),
      flowchart: flowchart,
      subflow_lookup: subflow_resolver.method(:find)
    ).call + loop_topology.errors.map { |error| format_loop_topology_error(error) }
  end

  private

  # Malformed loops and unsupported element types raise with the offending
  # element; any other structural problem makes #generate return nil.
  def structure_valid?
    errors = structure_errors
    return true if errors.empty?

    if (error = loop_topology.errors.first)
      raise Error.new(code: :invalid_loop_topology, message: I18n.t("errors.messages.invalid"),
        element_id: error[:element_id], element_type: "loop", details: [error[:reason]])
    end
    unsupported = elements.select { |element| StructureValidator::UNSUPPORTED_STRUCTURAL_TYPES.include?(element["type"]) }
    if unsupported.any?
      raise Error.new(
        code: :unsupported_structural_element,
        message: I18n.t("maint_core.flowcharts.structure_errors.unsupported_elements"),
        details: unsupported.map { |element| "#{element['id']}:#{element['type']}" }
      )
    end

    log_warn "Flowchart validation failed for #{flowchart.id}: #{errors.join(', ')}"
    false
  end

  def loop_topology
    @loop_topology ||= LoopTopology.new(elements, connections)
  end

  def format_loop_topology_error(error)
    I18n.t(
      "code_generator_validation.loop_topology.message",
      element_id: error[:element_id],
      reason: I18n.t("code_generator_validation.loop_topology.#{error[:reason]}"),
      invalid: I18n.t("errors.messages.invalid")
    )
  end

  def build_topological_order
    @topological_order ||= GraphBuilder.new(elements, loop_topology.forward_connections).topological_order
  end

  def build_element_io_index
    ElementIoIndex.new(
      elements,
      connections,
      topological_order_provider: method(:build_topological_order),
      loop_topology: loop_topology,
      scope: activity_class_name
    ).build
  end

  def activity_class_name
    @name_deriver.derive_activity_class_name(flowchart.name)
  end

  def header(steps)
    HeaderBuilder.new(flowchart: flowchart, elements: elements, bound_entity: bound_entity).build(steps)
  end

  def subflow_resolver
    @subflow_resolver ||= SubflowResolver.new(flowchart, finder: method(:load_subflow_for_current_owner))
  end

  # Runtime execution overrides this to embed launched flowcharts only.
  def load_subflow_for_current_owner(flowchart_id)
    SubflowResolver.visible_to(flowchart, flowchart_id)
  end

  def outgoing_connections(element_id)
    @outgoing_connections ||= connections.group_by { |connection| connection["from"] }
    NameDeriver.order_by_port(@outgoing_connections.fetch(element_id, []))
  end

  # Decisions get one Routes signal per outgoing connection; loop headers a
  # Done signal for their exit.
  def bind_routes(steps)
    used_modules = {}
    steps.select(&:decision?).each do |step|
      step.route_module, step.branches = @name_deriver.bind_branches(
        outgoing_connections(step.element_id), step_name: step.method_name, used_modules: used_modules
      )
    end
    steps.select(&:loop?).each do |step|
      region = loop_topology.regions[step.element_id]
      next unless region

      exit_connection = outgoing_connections(step.element_id).find { |connection| connection["to"] == region[:exit_id] }
      step.route_module, done = @name_deriver.bind_loop_done(
        exit_connection, step_name: step.method_name, used_modules: used_modules
      )
      step.done_signal = done[:signal]
      step.done_connection_id = done[:connection_id]
      step.body_id = region[:head_id]
      step.exit_id = region[:exit_id]
    end
  end

  def plan_wiring(steps)
    plan = WiringPlanner.new(
      descriptors: steps.map { |step| planner_descriptor(step) },
      decision_branches: steps.select(&:branches).to_h { |step| [step.method_name.to_sym, step.branches] },
      stepless_end_ids: elements.select { |element| self.class.stepless_end?(element) }.to_set { |element| element["id"].to_s }
    ).call
    by_id = steps.index_by { |step| step.method_name.to_sym }
    plan.step_plans.each do |item|
      next unless (step = by_id[item.id])

      step.magnetic = item.magnetic
      step.outputs = item.outputs
    end
    plan
  end

  # Maps the generated steps, routes and ends back to canvas element and
  # connection ids for the trace view and the diagram.
  def canvas(steps, plan)
    {
      steps: steps.to_h { |step| [step.method_name.to_sym, step.element_id.to_s] },
      routes: plan.routes,
      ends: plan.ends
    }
  end

  def planner_descriptor(step)
    descriptor = {
      id: step.method_name.to_sym,
      element_id: step.element_id,
      kind: step.kind,
      successors: outgoing_connections(step.element_id).map { |connection| connection["to"] }
    }
    return descriptor unless step.loop?

    descriptor.merge(
      body_id: step.body_id,
      exit_id: step.exit_id,
      done_signal: step.done_signal,
      done_connection_id: step.done_connection_id
    )
  end
end
