# frozen_string_literal: true

class ActivityGenerator
  # Builds the comment header block placed above the generated Activity class.
  class HeaderBuilder
    def initialize(flowchart:, elements:, bound_entity:)
      @flowchart = flowchart
      @elements = elements
      @bound_entity = bound_entity
    end

    # @param steps [Array<Hash>] DFS-collected step hashes (used for the Subflows line)
    # @return [String]
    def build(steps = [])
      lines = [
        "# frozen_string_literal: true",
        "#",
        generated_from_line,
        bound_entity_line
      ]
      subflows = subflows_line(steps)
      lines << subflows if subflows
      lines.join("\n")
    end

    private

    def generated_from_line
      name = ActivityGenerator.safe_comment_text(@flowchart.name)
      id = @flowchart.respond_to?(:id) ? @flowchart.id : nil
      prefix = id ? "flowchart ##{id.to_i}" : "flowchart"
      "# Generated from #{prefix} \"#{name}\". Do not edit; regenerate it from the flowchart editor."
    end

    def bound_entity_line
      return "# Bound entity: supplied at runtime by the submitting page" unless @bound_entity

      "# Checked against entity: #{ActivityGenerator.safe_comment_text(@bound_entity.display_label)}"
    end

    def subflows_line(steps)
      items = Array(steps).filter_map { |step| format_subflow(step[:subprocess]) }
      return if items.empty?

      "# Subflows: #{items.join(", ")}"
    end

    def format_subflow(info)
      return if info.blank?

      name = ActivityGenerator.safe_comment_text(info[:subflow_name])
      klass = ActivityGenerator.safe_comment_text(info[:activity_class_name])
      id = info[:flowchart_id]
      id_part = id.nil? ? " (\"#{name}\")" : " (##{id.to_i} \"#{name}\")"
      "#{klass}#{id_part}"
    end
  end
end
