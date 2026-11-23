# frozen_string_literal: true

require "timeout"
require "trailblazer/developer"

# ActivityTracer
#
# Executes a generated Trailblazer Activity with tracing enabled using
# Trailblazer::Developer::Trace. Captures the execution trace and provides
# structured results for visualization.
#
# @example
#   tracer = ActivityTracer.new(flowchart)
#   result = tracer.call(params: { name: "Test" })
#   result.success?      # => true/false
#   result.trace         # => formatted trace output
#   result.trace_nodes   # => structured trace data
#
class ActivityTracer
  include ActivityClassBuilder
  include Loggable
  Result = Struct.new(:success?, :signal, :ctx, :trace, :trace_nodes, :error, :queries, :timeout?, :truncated, keyword_init: true)

  # Hard cap on a single traced execution. Long-running flowcharts are aborted
  # and reported as a timeout Result rather than hanging the request.
  EXECUTION_TIMEOUT_SECONDS = 10

  # Owner test-run payload cap. The Trailblazer Trace::Stack itself still
  # grows for every executed step; we stop assembling Result#trace_nodes
  # (and skip Trace::Present) after this many After snapshots.
  MAX_TRACE_NODES = 500

  # Per-step ctx snapshots are best-effort debugging sugar: cap how many nodes
  # carry one, and clamp huge string values so the JSON payload stays sane.
  MAX_CTX_SNAPSHOTS = 50
  MAX_SNAPSHOT_STRING_LENGTH = 2000

  # Keys whose values must never reach the browser.
  SENSITIVE_KEY_PATTERN = /password|token|secret|credential|api_key/i

  attr_reader :flowchart

  def initialize(flowchart)
    @flowchart = flowchart
  end

  # Values under password/token/secret/credential/api_key keys must never
  # reach the browser. Shared by per-step snapshots and the final ctx payload.
  def self.redact_sensitive_keys(value)
    case value
    when Hash
      value.to_h do |k, v|
        [k, k.to_s.match?(SENSITIVE_KEY_PATTERN) ? "[REDACTED]" : redact_sensitive_keys(v)]
      end
    when Array
      value.map { |v| redact_sensitive_keys(v) }
    else
      value
    end
  end

  def call(input = {}, **kwargs)
    # Execution, including owner previews, uses the runtime child guard. The
    # caller may preview an unpublished parent; only its children must be
    # tenant-accessible and launched. Diagram/introspection callers of
    # ActivityClassBuilder do not enter this execution facade.
    trace = kwargs.fetch(:trace, true)
    kwargs = kwargs.except(:trace)
    input = kwargs if kwargs.any?
    if flowchart.is_a?(Flowchart)
      @flowchart = FlowchartRuntime::RuntimeFlowchart.new(flowchart, preview: !flowchart.launched?)
    end
    return error_result(translated_error(:no_activity_code)) if flowchart.activity.blank?

    activity_class = build_activity_class(
      flowchart.activity,
      entity: input[:bound_entity],
      flowchart: flowchart
    )
    return error_result(translated_error(:failed_to_build)) unless activity_class
    return error_result(translated_error(:must_regenerate)) if trace && !canvas_map?(activity_class)

    log_debug "Built activity class: #{activity_class.name || activity_class.to_s}"
    log_debug "Input context keys: #{input.keys}"

    input = input.merge(params: input[:params].to_h.with_indifferent_access) if input[:params].respond_to?(:to_h)
    input = input.merge(flowchart_id: flowchart.id)

    if trace
      execute_with_trace(activity_class, input)
    else
      execute_without_trace(activity_class, input)
    end
  rescue StandardError => e
    log_error "Execution error: #{e.class}: #{e.message}"
    log_error e.backtrace.first(10).join("\n")
    error_result(translated_error(:execution_failed))
  end

  private

  def execute_without_trace(activity_class, input)
    log_debug "Starting untraced execution..."

    signal, (ctx, _flow_options) = FlowchartRuntime::RunContext.with_deadline(EXECUTION_TIMEOUT_SECONDS) do
      Timeout.timeout(EXECUTION_TIMEOUT_SECONDS) do
        # Through the taskWrap, as traced runs are: a Subprocess's variable
        # mapping (In/Inject) only applies there.
        Trailblazer::Activity::TaskWrap.invoke(activity_class, [input, {}])
      end
    end

    log_debug "Execution completed with signal: #{signal.class.name}"

    Result.new(
      success?: signal.to_h[:semantic] == :success,
      signal: signal,
      ctx: ctx,
      trace: nil,
      trace_nodes: [],
      error: nil,
      queries: [],
      timeout?: false,
      truncated: false
    )
  rescue Timeout::Error
    log_error "Execution timed out after #{EXECUTION_TIMEOUT_SECONDS} seconds"
    timeout_result
  rescue StandardError => e
    log_error "Execution error: #{e.class}: #{e.message}"
    log_error e.backtrace.first(10).join("\n")
    error_result(translated_error(:execution_failed))
  end

  def execute_with_trace(activity_class, input)
    log_debug "Starting traced execution..."
    stack = Trailblazer::Developer::Trace::Stack.new

    begin
      trace_result, queries = FlowchartRuntime::RunContext.with_deadline(EXECUTION_TIMEOUT_SECONDS) do
        Timeout.timeout(EXECUTION_TIMEOUT_SECONDS) do
          FlowchartRuntime::QueryLogger.capture do
            Trailblazer::Developer::Trace.invoke(
              activity_class,
              [input, { stack: stack }]
            )
          end
        end
      end
    rescue Timeout::Error
      log_error "Execution timed out after #{EXECUTION_TIMEOUT_SECONDS} seconds"
      return timeout_result
    rescue StandardError => e
      log_error "Execution error: #{e.class}: #{e.message}"
      log_error e.backtrace.first(10).join("\n")
      return traced_error_result(activity_class, stack, e)
    end

    complete_stack, signal, (ctx, _flow_options) = trace_result
    stack = complete_stack || stack

    log_debug "Execution completed with signal: #{signal.class.name}"

    trace_nodes, truncated = build_trace_nodes(stack, activity_class)
    trace_output = truncated ? nil : present_trace(stack)

    log_debug "Trace nodes count: #{trace_nodes.size}"
    log_debug "Final ctx keys: #{ctx.keys}" if ctx.is_a?(Hash)

    Result.new(
      success?: signal.to_h[:semantic] == :success,
      signal: signal,
      ctx: ctx,
      trace: trace_output,
      trace_nodes: trace_nodes,
      error: nil,
      queries: queries,
      timeout?: false,
      truncated: truncated
    )
  end

  def traced_error_result(activity_class, stack, error)
    trace_nodes, truncated = build_trace_nodes(stack, activity_class, raised: true)
    Result.new(
      success?: false,
      signal: nil,
      ctx: {},
      trace: truncated ? nil : present_trace(stack),
      trace_nodes: trace_nodes,
      error: translated_error(:execution_failed),
      queries: [],
      timeout?: false,
      truncated: truncated
    )
  end

  def present_trace(stack)
    Trailblazer::Developer::Trace::Present.(stack)
  rescue StandardError
    nil
  end

  # Build structured trace data for UI visualization. Stops after
  # MAX_TRACE_NODES assembled nodes (execution order). The underlying
  # Trailblazer stack still holds every snapshot.
  def build_trace_nodes(stack, activity_class, raised: false)
    snapshots = stack.to_a
    nodes_meta = activity_class.to_h[:nodes]
    canvas = activity_canvas(activity_class)
    outer_activity = outer_activity_from(snapshots)
    snapshots_captured = 0
    last_step_id = nil
    last_step_semantic = nil
    nodes = []
    truncated = false

    snapshots.each do |snapshot|
      next unless snapshot.is_a?(Trailblazer::Developer::Trace::Snapshot::After)
      next unless outer_activity.nil? || snapshot.activity.equal?(outer_activity)

      task = snapshot.task
      next if task == activity_class

      node_meta = nodes_meta[task]
      next unless node_meta

      node_id = node_meta[:id].to_s
      next if node_id == "collect_errors"

      signal = snapshot.data[:signal]
      semantic = output_semantic(node_meta, signal)

      unless terminal_id?(node_id)
        last_step_id = node_id
        last_step_semantic = semantic
      end

      # End-with-response is a Railway step (CANVAS[:steps]) but represents the
      # canvas End. Omit it on success so that element appears once, as
      # End.success; a failing End step stays visible.
      next if semantic == :success && end_with_response_step?(canvas, node_id)

      if nodes.size >= MAX_TRACE_NODES
        truncated = true
        break
      end

      node = assemble_trace_node(
        node_id: node_id,
        node_meta: node_meta,
        signal: signal,
        semantic: semantic,
        canvas: canvas,
        last_step_id: last_step_id,
        last_step_semantic: last_step_semantic
      )

      if snapshots_captured < MAX_CTX_SNAPSHOTS &&
         (ctx_snapshot = extract_ctx_snapshot(snapshot, stack.variable_versions))
        node[:ctx_snapshot] = ctx_snapshot
        snapshots_captured += 1
      end

      nodes << node
    end

    if raised && !truncated
      append_raised_node!(nodes, snapshots, activity_class, nodes_meta, canvas, outer_activity)
      if nodes.size > MAX_TRACE_NODES
        truncated = true
        nodes = nodes.first(MAX_TRACE_NODES)
      end
    end

    [nodes, truncated]
  end

  # Best-effort per-step context snapshot (BY DESIGN): reconstruct the ctx the
  # step returned from the trace's variable-version changeset, sanitize it, and
  # clamp oversized strings. Any failure simply omits the key — snapshot
  # extraction must never fail the run.
  def extract_ctx_snapshot(snapshot, variable_versions)
    ctx = Trailblazer::Developer::Trace::Snapshot.snapshot_ctx_for(snapshot, variable_versions)
    return nil unless ctx.is_a?(Hash)

    # snapshot_ctx_for yields {name => {value: <inspected String>, has_changed: bool}};
    # the UI only needs name => value.
    values = ctx.transform_values { |entry| entry.is_a?(Hash) && entry.key?(:value) ? entry[:value] : entry }

    truncate_strings(redact_sensitive_keys(ContextSanitizer.sanitize(values)))
  rescue StandardError => e
    log_debug "ctx snapshot extraction skipped - #{e.class}: #{e.message}"
    nil
  end

  def redact_sensitive_keys(value)
    self.class.redact_sensitive_keys(value)
  end

  # Recursively truncate String values longer than MAX_SNAPSHOT_STRING_LENGTH.
  def truncate_strings(value)
    case value
    when String
      return value if value.length <= MAX_SNAPSHOT_STRING_LENGTH

      "#{value[0, MAX_SNAPSHOT_STRING_LENGTH]}…(truncated)"
    when Hash
      value.transform_values { |v| truncate_strings(v) }
    when Array
      value.map { |v| truncate_strings(v) }
    else
      value
    end
  end

  TERMINAL_SEMANTICS = [:success, :failure].freeze

  def assemble_trace_node(node_id:, node_meta:, signal:, semantic:, canvas:, last_step_id:, last_step_semantic:)
    status = status_for(semantic, signal)
    node = {
      id: node_id,
      element_id: element_id_for(node_id, canvas, last_step_id, last_step_semantic),
      label: label_for(node_id, canvas, last_step_id, last_step_semantic),
      status: status,
      signal: signal_name(signal)
    }
    if route_semantic?(semantic)
      node[:branch] = branch_for(canvas, node_id, semantic)
    end
    node
  end

  def element_id_for(node_id, canvas, last_step_id, last_step_semantic)
    return nil if canvas.nil?

    if node_id == "Start.default"
      start_element_id
    elsif terminal_id?(node_id)
      return nil if node_id == "End.failure"

      end_element_id(canvas, last_step_id, last_step_semantic)
    else
      step_element_id(canvas, node_id)
    end
  end

  def label_for(node_id, canvas, last_step_id, last_step_semantic)
    if node_id == "Start.default"
      I18n.t("flowchart_elements.trace.start")
    elsif node_id == "End.failure"
      I18n.t("flowchart_elements.trace.failure")
    elsif terminal_id?(node_id)
      mapped = canvas && end_element_id(canvas, last_step_id, last_step_semantic)
      element_label(mapped) || I18n.t("flowchart_elements.trace.success")
    else
      element_label(step_element_id(canvas, node_id)) || derive_node_label(node_id)
    end
  end

  def status_for(semantic, signal)
    case semantic&.to_sym
    when :success then "success"
    when :failure then "failure"
    else
      return "success" if route_semantic?(semantic)

      name = signal_name(signal)
      return "success" if name.include?("Right")
      return "failure" if name.include?("Left")

      "unknown"
    end
  end

  def output_semantic(node_meta, signal)
    Array(node_meta&.[](:outputs)).each do |output|
      return output.semantic if output.signal == signal
    end

    if signal.is_a?(Class)
      name = signal.name.to_s
      return :success if name.include?("Right")
      return :failure if name.include?("Left")
    end
    return signal.to_h[:semantic] if signal.respond_to?(:to_h) && signal.to_h[:semantic]

    nil
  end

  def route_semantic?(semantic)
    semantic && !TERMINAL_SEMANTICS.include?(semantic.to_sym)
  end

  def terminal_id?(node_id)
    id = node_id.to_s
    id == "Start.default" || id.start_with?("End.")
  end

  def signal_name(signal)
    return "" if signal.nil?

    (signal.is_a?(Class) ? signal.name : signal.class.name).to_s.split("::").last
  end

  def canvas_map?(activity_class)
    activity_class.const_defined?(:CANVAS, false) && activity_class.const_get(:CANVAS).is_a?(Hash)
  end

  def activity_canvas(activity_class)
    return nil unless canvas_map?(activity_class)

    activity_class.const_get(:CANVAS)
  end

  def outer_activity_from(snapshots)
    after = snapshots.find { |snapshot| snapshot.is_a?(Trailblazer::Developer::Trace::Snapshot::After) }
    (after || snapshots.first)&.activity
  end

  def append_raised_node!(nodes, snapshots, activity_class, nodes_meta, canvas, outer_activity)
    source = snapshots.reverse.find do |snapshot|
      next false unless outer_activity.nil? || snapshot.activity.equal?(outer_activity)

      snapshot.is_a?(Trailblazer::Developer::Trace::Snapshot::Before) ||
        snapshot.is_a?(Trailblazer::Developer::Trace::Snapshot::After)
    end
    return unless source

    task = source.task
    return if task == activity_class

    node_meta = nodes_meta[task]
    return unless node_meta

    node_id = node_meta[:id].to_s
    return if node_id == "collect_errors" || terminal_id?(node_id)

    existing = nodes.find { |node| node[:id] == node_id }
    if existing
      existing[:status] = "failure"
      existing.delete(:branch)
      return
    end

    nodes << {
      id: node_id,
      element_id: step_element_id(canvas, node_id),
      label: element_label(step_element_id(canvas, node_id)) || derive_node_label(node_id),
      status: "failure",
      signal: signal_name(source.respond_to?(:data) ? source.data[:signal] : nil)
    }
  end

  def step_element_id(canvas, step_id)
    return nil if canvas.nil?

    steps = canvas[:steps] || {}
    steps[step_id.to_sym].presence
  end

  def end_element_id(canvas, step_id, semantic)
    return nil if canvas.nil? || step_id.nil?

    if semantic
      ends = canvas[:ends] || {}
      step_ends = ends[step_id.to_sym] || {}
      mapped = step_ends[semantic.to_sym].presence
      return mapped if mapped
    end

    # Stepless Ends live in CANVAS[:ends]. An End that writes a response is
    # itself the last executed step (CANVAS[:steps]); use that element.
    element_id = step_element_id(canvas, step_id)
    canvas_end_element?(element_id) ? element_id : nil
  end

  def end_with_response_step?(canvas, node_id)
    return false if terminal_id?(node_id)

    canvas_end_element?(step_element_id(canvas, node_id))
  end

  def canvas_end_element?(element_id)
    return false if element_id.blank?

    Array(flowchart.elements).find { |element| element["id"].to_s == element_id.to_s }&.[]("type") == "end"
  end

  def branch_for(canvas, step_id, semantic)
    routes = canvas.is_a?(Hash) ? (canvas[:routes] || {}) : {}
    step_routes = routes[step_id.to_sym] || {}
    connection_id = step_routes[semantic.to_sym]
    connection_label(connection_id) || semantic.to_s
  end

  def start_element_id
    Array(flowchart.elements).find { |element| element["type"] == "start" }&.dig("id")&.to_s
  end

  def element_label(element_id)
    return nil if element_id.blank?

    Array(flowchart.elements).find { |element| element["id"].to_s == element_id.to_s }&.[]("label").presence
  end

  def connection_label(connection_id)
    return nil if connection_id.blank?

    Array(flowchart.connections).find { |connection| connection["id"].to_s == connection_id.to_s }&.[]("label").presence
  end

  def translated_error(key, **interpolations)
    I18n.t("flowchart_elements.trace.errors.#{key}", **interpolations)
  end

  def error_result(message)
    Result.new(
      success?: false,
      signal: nil,
      ctx: {},
      trace: nil,
      trace_nodes: [],
      error: message,
      queries: [],
      timeout?: false,
      truncated: false
    )
  end

  def timeout_result
    Result.new(
      success?: false,
      signal: nil,
      ctx: {},
      trace: nil,
      trace_nodes: [],
      error: translated_error(:timed_out, seconds: EXECUTION_TIMEOUT_SECONDS),
      queries: [],
      timeout?: true,
      truncated: false
    )
  end
end
