# frozen_string_literal: true

class ActivityGenerator
  # The editor's loop topology is header -> body -> header, plus header -> exit.
  # Only backedges closing such single-entry regions are removed for DAG analysis.
  # A header going directly to End may have an empty body. Other body-less,
  # nested/overlapping regions and body-to-exit shortcuts are rejected.
  class LoopTopology
    attr_reader :regions, :errors, :connections

    def initialize(elements, connections)
      @elements = elements.index_by { |element| element["id"] }
      @connections = connections
      @regions = {}
      @errors = []
      @outgoing = connections.group_by { |edge| edge["from"] }
      elements.select { |element| element["type"] == "loop" }.each { |element| analyze(element["id"]) }
      @iteration_ends = regions.transform_values { Object.new.freeze }
    end

    def forward_connections
      connections.reject { |edge| backedge?(edge) }
    end

    # A backedge is a successful end of this iteration, not a missing branch.
    # Use an opaque sink per body so topology analysis keeps branch cardinality,
    # order and match values without routing back into the loop header.
    def routing_connections
      connections.map do |edge|
        backedge?(edge) ? edge.merge("to" => @iteration_ends.fetch(edge["to"])) : edge
      end
    end

    # One-iteration dataflow. A body can contribute outputs to the continuation,
    # but never supplies inputs to an earlier read on the first iteration.
    def dataflow_connections
      connections.map do |edge|
        backedge?(edge) ? edge.merge("to" => regions.fetch(edge["to"])[:exit_id]) : edge
      end
    end

    private

    def backedge?(edge)
      regions[edge["to"]]&.fetch(:body_ids)&.include?(edge["from"])
    end

    def analyze(header)
      outgoing = @outgoing.fetch(header, [])
      heads = outgoing.select { |edge| reachable(edge["to"], stop: header).include?(header) }
      if heads.empty? && outgoing.size == 1 && @elements[outgoing.first["to"]]&.dig("type") == "end"
        regions[header] = { body_ids: Set.new, exit_id: outgoing.first["to"] }
        return
      end
      return invalid(header, :loop_requires_body_and_exit) unless heads.size == 1 && outgoing.size == 2

      head = heads.first["to"]
      exit_id = (outgoing - heads).first["to"]
      body = reachable(head, stop: header) - [header]
      return invalid(header, :loop_body_empty) if body.empty?
      return invalid(header, :loop_body_escape) if body.include?(exit_id) || body.any? { |id| !reachable(id, stop: header).include?(header) }
      return invalid(header, :nested_loop) if body.any? { |id| @elements[id]&.dig("type") == "loop" }
      return invalid(header, :loop_body_external_entry) if connections.any? { |edge|
        body.include?(edge["to"]) && !body.include?(edge["from"]) && !(edge["from"] == header && edge["to"] == head)
      }
      return invalid(header, :overlapping_loops) if regions.values.any? { |region| (region[:body_ids] & body).any? }

      regions[header] = { body_ids: body, head_id: head, exit_id: exit_id }
    end

    def invalid(header, reason)
      errors << { element_id: header, reason: reason }
    end

    def reachable(start, stop:)
      seen = Set.new
      queue = [start]
      while (id = queue.shift)
        next unless seen.add?(id)
        next if id == stop

        queue.concat(@outgoing.fetch(id, []).map { |edge| edge["to"] })
      end
      seen
    end
  end
end
