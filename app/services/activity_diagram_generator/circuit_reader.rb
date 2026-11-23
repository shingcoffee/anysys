# frozen_string_literal: true

class ActivityDiagramGenerator
  # Reads a compiled Railway circuit into a Graph, mapping it back to the
  # canvas through the activity's CANVAS constant:
  #
  # - each step takes its element's label and shape;
  # - End.success splits back into the End elements each step reaches
  #   (CANVAS[:ends]); an End that writes a response is itself a step and is
  #   drawn as that terminal;
  # - collect_errors and End.failure collapse into one Failure terminal;
  # - decision branches and loop exits carry their connection's label.
  class CircuitReader
    START = "Start.default"
    SUCCESS = "End.success"
    FAILURE = "End.failure"
    COLLECT_ERRORS = "collect_errors"
    PLUMBING = [SUCCESS, FAILURE, COLLECT_ERRORS].freeze
    TERMINAL_SEMANTICS = %i[success failure].freeze
    KIND_BY_TYPE = { "decision" => :decision, "loop" => :loop, "subflow" => :subflow, "end" => :end }.freeze

    def initialize(activity_class, flowchart)
      schema = activity_class.to_h
      @nodes_meta = schema[:nodes]
      @circuit = schema[:circuit].to_h[:map]
      @canvas = canvas_of(activity_class)
      @elements = Array(flowchart.elements).index_by { |element| element["id"].to_s }
      @connections = Array(flowchart.connections)
      @nodes = {}
      @ids = {}
      @edges = []
    end

    # @return [Graph]
    def call
      @nodes_meta.each_value { |attrs| declare(attrs) }
      @circuit.each { |task, outputs| connect(@nodes_meta[task], outputs) }
      failure = @nodes.delete(FAILURE)
      Graph.new(nodes: [*@nodes.values, *failure], edges: @edges.uniq)
    end

    private

    def declare(attrs)
      id = attrs[:id].to_s
      return if PLUMBING.include?(id)
      return @nodes[id] = Graph::Node.new(id: mermaid_id("n", "start"), kind: :start, label: start_label) if id == START

      element = @elements[step_element_id(id)]
      kind = element ? KIND_BY_TYPE.fetch(element["type"], :step) : fallback_kind(attrs)
      @nodes[id] = Graph::Node.new(id: mermaid_id("s", id), kind: kind, label: element&.dig("label").presence || id.humanize)
    end

    def connect(attrs, outputs)
      from = attrs[:id].to_s
      return if PLUMBING.include?(from)

      source = @nodes.fetch(from)
      outputs.each do |signal, task|
        semantic = Array(attrs[:outputs]).find { |output| output.signal == signal }&.semantic
        to = @nodes_meta[task][:id].to_s
        if [COLLECT_ERRORS, FAILURE].include?(to)
          add_edge(source, failure_node, failure: true)
        elsif to == SUCCESS
          next if source.kind == :end

          end_id = @canvas.dig(:ends, from.to_sym, semantic)
          add_edge(source, end_node(end_id), label: edge_label(from, semantic, end_id, source.kind))
        else
          add_edge(source, @nodes.fetch(to), label: edge_label(from, semantic, step_element_id(to), source.kind))
        end
      end
    end

    def add_edge(source, target, label: nil, failure: false)
      @edges << Graph::Edge.new(from: source.id, to: target.id, label: label, failure: failure)
    end

    def edge_label(from, semantic, target_element_id, kind)
      return route_label(from, semantic, kind) if semantic && !TERMINAL_SEMANTICS.include?(semantic)

      label = connection_between(step_element_id(from) || start_element_id(from), target_element_id)&.dig("label").presence
      label || (I18n.t("maint_core.flowcharts.show.diagram.loop_repeat") if kind == :loop)
    end

    # A decision branch or loop exit: the connection's label, else what the
    # editor shows for its match value.
    def route_label(from, semantic, kind)
      connection = connection_by_id(@canvas.dig(:routes, from.to_sym, semantic))
      return connection["label"] if connection&.dig("label").present?
      return I18n.t("common.actions.done") if kind == :loop

      match_label(connection&.dig("matchValue")) || semantic.to_s.humanize
    end

    def match_label(match_value)
      case match_value.to_s.strip.downcase
      when "true" then I18n.t("maint_core.flowcharts.editor.property_editor.yes_match_label")
      when "false" then I18n.t("maint_core.flowcharts.editor.property_editor.no_match_label")
      when "" then I18n.t("maint_core.flowcharts.editor.property_editor.otherwise_label")
      else match_value.to_s.strip
      end
    end

    def failure_node
      @nodes[FAILURE] ||= Graph::Node.new(id: mermaid_id("n", "failure"), kind: :failure,
        label: I18n.t("flowchart_elements.trace.failure"))
    end

    # The End element a step reaches; without a CANVAS entry, the flowchart's
    # only response-less End, else a generic one.
    def end_node(element_id)
      element = @elements[element_id.to_s] || sole_stepless_end
      key = element ? "end:#{element['id']}" : SUCCESS
      @nodes[key] ||= Graph::Node.new(
        id: mermaid_id("e", element ? element["id"] : "success"),
        kind: :end,
        label: element&.dig("label").presence || I18n.t("flowchart_elements.trace.success")
      )
    end

    def sole_stepless_end
      ends = @elements.values.select { |element| ActivityGenerator.stepless_end?(element) }
      ends.first if ends.one?
    end

    def start_label
      @elements.values.find { |element| element["type"] == "start" }&.dig("label").presence ||
        I18n.t("flowchart_elements.trace.start")
    end

    def start_element_id(from)
      @elements.values.find { |element| element["type"] == "start" }&.dig("id") if from == START
    end

    # A Subprocess keeps its child's End signals as outputs.
    def fallback_kind(attrs)
      Array(attrs[:outputs]).any? { |output| output.signal.is_a?(Trailblazer::Activity::End) } ? :subflow : :step
    end

    def step_element_id(step_id)
      @canvas.dig(:steps, step_id.to_sym)
    end

    def connection_by_id(id)
      @connections.find { |connection| connection["id"].to_s == id.to_s } if id.present?
    end

    def connection_between(from_element_id, to_element_id)
      return if from_element_id.blank? || to_element_id.blank?

      @connections.find do |connection|
        connection["from"].to_s == from_element_id.to_s && connection["to"].to_s == to_element_id.to_s
      end
    end

    # Mermaid ids are prefixed so no step name can collide with a keyword
    # such as `end`.
    def mermaid_id(prefix, raw)
      @ids[[prefix, raw.to_s]] ||= begin
        base = "#{prefix}_#{raw.to_s.gsub(/[^A-Za-z0-9_]/, '_')}"
        taken = @ids.values.to_set
        candidate = base
        suffix = 1
        candidate = "#{base}_#{suffix += 1}" while taken.include?(candidate)
        candidate
      end
    end

    def canvas_of(activity_class)
      return {} unless activity_class.const_defined?(:CANVAS, false)

      canvas = activity_class.const_get(:CANVAS)
      canvas.is_a?(Hash) ? canvas.deep_symbolize_keys : {}
    end
  end
end
