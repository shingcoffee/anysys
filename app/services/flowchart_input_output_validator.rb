# app/services/flowchart_input_output_validator.rb
# frozen_string_literal: true

class FlowchartInputOutputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)
  CONFIG_PATH = Rails.root.join("config", "flowchart_validation.yml").freeze

  def self.call(flowchart)
    new(flowchart).call
  end

  def initialize(flowchart)
    @flowchart = flowchart
    @errors = []
  end

  def call
    validate_inputs
    Result.new(valid?: @errors.empty?, errors: @errors)
  end

  private

  def validate_inputs
    predecessors = build_predecessors
    element_outputs = collect_element_outputs

    elements.each do |element|
      validate_element_inputs(element, predecessors, element_outputs)
    end
  end

  def validate_element_inputs(element, predecessors, element_outputs)
    element_id = element["id"]
    element_type = element["type"]
    properties = hash_row(element["properties"])

    pins = CodeGenerators::IoExtractor.call_element(
      element_type: element_type,
      properties: properties
    )

    input_overrides = array_of_hashes(properties.dig("io_overrides", "inputs"))
    override_map = input_overrides.each_with_object({}) do |o, h|
      h[o["pin"]] = o["override_key"]
    end

    upstream_ids = predecessors[element_id] || []
    available_outputs = upstream_ids.flat_map { |id| element_outputs[id]&.to_a || [] }.to_set

    own_raw_outputs       = (pins[:outputs] || []).map { |o| o[:pin] }.to_set
    own_effective_outputs = element_outputs[element_id] || Set.new

    (pins[:inputs] || []).each do |pin|
      pin_name      = pin[:pin]
      overridden    = override_map.key?(pin_name)
      effective_key = overridden ? override_map[pin_name] : pin_name

      next if effective_key == ""
      next if implicit_keys.include?(effective_key)
      # Self-reference: an element's own write can satisfy its own read. When the
      # reader has no input override, the raw pin pairs with the raw self-write
      # (runtime rewrites both sides consistently through output rename). When the
      # reader has an input override, we match the effective key against the
      # element's effective (post-rename) self-outputs.
      next if !overridden && own_raw_outputs.include?(pin_name)
      next if own_effective_outputs.include?(effective_key)
      next if available_outputs.include?(effective_key)

      @errors << {
        element_id: element_id,
        element_label: element["label"] || element_id,
        missing_input: effective_key,
        message: I18n.t("maint_core.flowcharts.server_validation.missing_input", key: effective_key)
      }
    end
  end

  def implicit_keys
    @implicit_keys ||= begin
      config = YAML.load_file(CONFIG_PATH)
      Set.new(config["implicit_context_keys"] || [])
    end
  end

  def elements
    @elements ||= array_of_hashes(@flowchart.configuration_json&.dig("elements"))
  end

  def connections
    @connections ||= array_of_hashes(@flowchart.configuration_json&.dig("connections"))
  end

  def array_of_hashes(raw)
    raw.is_a?(Array) ? raw.select { |row| row.is_a?(Hash) } : []
  end

  def hash_row(raw)
    raw.is_a?(Hash) ? raw : {}
  end

  def build_predecessors
    reverse_graph = Hash.new { |h, k| h[k] = [] }
    elements.each { |el| reverse_graph[el["id"]] }

    ActivityGenerator::LoopTopology.new(elements, connections).dataflow_connections.each do |conn|
      reverse_graph[conn["to"]] << conn["from"] if reverse_graph.key?(conn["to"])
    end

    predecessors = {}
    elements.each do |el|
      predecessors[el["id"]] = compute_all_predecessors(el["id"], reverse_graph)
    end
    predecessors
  end

  def compute_all_predecessors(element_id, reverse_graph)
    visited = Set.new([element_id])
    queue = reverse_graph[element_id].dup

    while queue.any?
      current = queue.shift
      next if visited.include?(current)

      visited << current
      queue.concat(reverse_graph[current])
    end

    (visited - [element_id]).to_a
  end

  def collect_element_outputs
    outputs = {}

    elements.each do |element|
      element_id = element["id"]
      element_type = element["type"]
      properties = hash_row(element["properties"])

      pins = CodeGenerators::IoExtractor.call_element(
        element_type: element_type,
        properties: properties
      )

      output_overrides = array_of_hashes(properties.dig("io_overrides", "outputs"))
      override_map = output_overrides.each_with_object({}) do |o, h|
        h[o["pin"]] = o["renamed_to"]
      end

      effective_outputs = Set.new
      (pins[:outputs] || []).each do |pin|
        pin_name = pin[:pin]
        effective_key = override_map[pin_name] || pin_name
        effective_outputs << effective_key
      end

      outputs[element_id] = effective_outputs
    end

    outputs
  end
end
