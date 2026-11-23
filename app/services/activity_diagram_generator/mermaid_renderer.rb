# frozen_string_literal: true

class ActivityDiagramGenerator
  # Writes Graph nodes and edges as Mermaid flowchart source. Shapes and
  # colours follow the flowchart editor's palette; labels are quoted Mermaid
  # strings with every character Mermaid could parse escaped as an entity.
  class MermaidRenderer
    SHAPES = {
      start: ["([", "])"],
      end: ["([", "])"],
      failure: ["([", "])"],
      step: ["(", ")"],
      decision: ["{", "}"],
      loop: ["{{", "}}"],
      subflow: ["[[", "]]"]
    }.freeze

    # Tailwind 50 / 400 / 800 shades of each kind's editor colour.
    CLASS_DEFS = {
      start: "fill:#f0fdf4,stroke:#22c55e,color:#166534",
      step: "fill:#eff6ff,stroke:#60a5fa,color:#1e40af",
      decision: "fill:#fefce8,stroke:#facc15,color:#854d0e",
      loop: "fill:#faf5ff,stroke:#c084fc,color:#6b21a8",
      subflow: "fill:#eef2ff,stroke:#818cf8,color:#3730a3",
      end: "fill:#fef2f2,stroke:#f87171,color:#991b1b",
      failure: "fill:#dc2626,stroke:#b91c1c,color:#ffffff"
    }.freeze

    FAILURE_LINK_STYLE = "stroke:#f87171,stroke-width:1.5px"
    MAX_LABEL_LENGTH = 60

    # `%` would let a label open a `%%{init}%%` directive; the rest end or
    # re-type a quoted Mermaid string.
    ENTITIES = {
      '"' => "#quot;", "#" => "#35;", "&" => "#38;", "<" => "#lt;", ">" => "#gt;",
      "`" => "#96;", "%" => "#37;", "|" => "#124;", "\\" => "#92;"
    }.freeze
    ESCAPED = Regexp.union(ENTITIES.keys)
    INVISIBLE = /[\p{Cc}\u200E\u200F\u202A-\u202E\u2066-\u2069]/

    def initialize(nodes, edges)
      @nodes = nodes
      @edges = edges
    end

    def render
      [
        "flowchart TD",
        *@nodes.map { |node| "  #{node.id}#{shape(node)}" },
        *@edges.map { |edge| "  #{edge_source(edge)}" },
        *class_lines,
        failure_link_style
      ].compact.join("\n")
    end

    private

    def shape(node)
      opening, closing = SHAPES.fetch(node.kind)
      "#{opening}#{text(node.label)}#{closing}"
    end

    def edge_source(edge)
      return "#{edge.from} -.-> #{edge.to}" if edge.failure
      return "#{edge.from} --> #{edge.to}" if edge.label.blank?

      "#{edge.from} -->|#{text(edge.label)}| #{edge.to}"
    end

    # Class names carry a suffix because `end` is a Mermaid keyword.
    def class_lines
      groups = @nodes.group_by(&:kind)
      defs = groups.keys.map { |kind| "  classDef #{kind}Node #{CLASS_DEFS.fetch(kind)}" }
      assignments = groups.map { |kind, nodes| "  class #{nodes.map(&:id).join(',')} #{kind}Node" }
      defs + assignments
    end

    def failure_link_style
      indexes = @edges.each_index.select { |index| @edges[index].failure }
      "  linkStyle #{indexes.join(',')} #{FAILURE_LINK_STYLE}" if indexes.any?
    end

    def text(label)
      clean = label.to_s.gsub(INVISIBLE, " ").squish
      clean = "#{clean[0, MAX_LABEL_LENGTH - 1]}…" if clean.length > MAX_LABEL_LENGTH
      "\"#{clean.gsub(ESCAPED, ENTITIES)}\""
    end
  end
end
