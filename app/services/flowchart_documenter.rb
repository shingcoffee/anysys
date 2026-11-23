# frozen_string_literal: true

# FlowchartDocumenter
#
# Generates markdown documentation for a flowchart.
# Includes overview, flow description, elements table, and connections list.
#
class FlowchartDocumenter
  def initialize(flowchart)
    @flowchart = flowchart
    @elements = flowchart.elements
    @connections = flowchart.connections
  end

  def generate
    sections = []
    sections << "# #{@flowchart.name}\n"
    sections << "#{@flowchart.description}\n" if @flowchart.description.present?
    sections << "---\n"
    sections << "## Overview\n"
    sections << "- **Elements:** #{@elements.size}"
    sections << "- **Connections:** #{@connections.size}"
    sections << "- **Created:** #{@flowchart.created_at&.strftime('%Y-%m-%d')}"
    sections << ""
    sections << "## Flow Description\n"
    sections << generate_flow_narrative
    sections << ""
    sections << "## Elements\n"
    sections << generate_elements_table
    sections << ""
    sections << "## Connections\n"
    sections << generate_connections_list
    sections.join("\n")
  end

  private

  def generate_flow_narrative
    start_el = @elements.find { |el| el["type"] == "start" }
    return "No start element found." unless start_el

    visited = Set.new
    narrative = []
    traverse_narrative(start_el["id"], visited, narrative, 1)
    narrative.join("\n")
  end

  def traverse_narrative(element_id, visited, narrative, depth)
    return if visited.include?(element_id)
    visited.add(element_id)

    element = @elements.find { |el| el["id"] == element_id }
    return unless element

    indent = "  " * (depth - 1)
    type = element["type"].capitalize
    label = element["label"] || "(unnamed)"

    case element["type"]
    when "start"
      narrative << "#{indent}#{depth}. **Start** — #{label}"
    when "end"
      narrative << "#{indent}#{depth}. **End** — #{label}"
    when "process"
      steps = element.dig("properties", "steps") || []
      step_names = steps.map { |s| (s["selectionLabels"] || [s["action"]]).join(" ") }.join(" → ")
      narrative << "#{indent}#{depth}. **Process** — #{label}#{step_names.present? ? ": #{step_names}" : ""}"
    when "decision"
      expr = element.dig("properties", "condition", "expression")
      narrative << "#{indent}#{depth}. **Decision** — #{label}#{expr ? " (#{expr})" : ""}"
    when "loop"
      narrative << "#{indent}#{depth}. **Loop** — #{label}"
    else
      narrative << "#{indent}#{depth}. **#{type}** — #{label}"
    end

    # Follow connections
    outgoing = @connections.select { |c| c["from"] == element_id }
    outgoing.each do |conn|
      traverse_narrative(conn["to"], visited, narrative, depth + 1)
    end
  end

  def generate_elements_table
    lines = []
    lines << "| Type | Label | Description | Properties |"
    lines << "|------|-------|-------------|------------|"
    @elements.each do |el|
      type = el["type"]
      label = el["label"] || "(unnamed)"
      desc = el.dig("properties", "description") || ""
      props = summarize_properties(el)
      lines << "| #{type} | #{label} | #{desc.truncate(50)} | #{props} |"
    end
    lines.join("\n")
  end

  def generate_connections_list
    @connections.map { |c|
      from_el = @elements.find { |el| el["id"] == c["from"] }
      to_el = @elements.find { |el| el["id"] == c["to"] }
      from_label = from_el&.dig("label") || c["from"]
      to_label = to_el&.dig("label") || c["to"]
      label_text = c["label"] ? " [#{c['label']}]" : ""
      "- #{from_label} → #{to_label}#{label_text}"
    }.join("\n")
  end

  def summarize_properties(element)
    props = []
    steps = element.dig("properties", "steps")
    props << "#{steps.size} steps" if steps&.any?
    condition = element.dig("properties", "condition", "expression")
    props << "condition: #{condition}" if condition
    props.join(", ")
  end
end
